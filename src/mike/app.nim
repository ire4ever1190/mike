import router, context, common, errors
import helpers/[response, context]

import std/[httpcore, macros, options, asyncdispatch, parseutils, strtabs, terminal, cpuinfo]

import httpx

## This is a fully typesafe version of the API. All responses should be
## done by returning like a normal function. For getting data, [Context]
## can be used by using context hooks is strongly encouraged

# TODO Support future returns, better extraction like `createASyncHandler`
# TODO Support implicit path parameters

type
  Handler* = AsyncHandler
  App* = object
    ## Entrypoint for a Mike application.
    ## All routes get registered to this
    router: Router[AsyncHandler]
      ## Routes requests to their handlers

using mapp: var App

proc initApp*(): App =
  ## Creates a new Mike app.
  return App()

func getPathAndQuery(url: sink string): tuple[path, query: string] {.inline.} =
  ## Returns the path and query string from a url
  let pathLength = url.parseUntil(result.path, '?')
  # Add query string that comes after
  if pathLength != url.len():
      result.query = url[pathLength + 1 .. ^1]

proc extractEncodedParams(input: sink string, table: var StringTableRef) {.inline.} =
  ## Extracts the parameters into a table
  for (key, value) in common.decodeQuery(input):
    table[key] = value

proc makeOnRequest(app: App): OnRequest {.inline.} =
  proc onRequest(req: Request): Future[void] {.async.} =
    ## Handles running the requests
    {.gcsafe.}:
      if req.path.isSome() and req.httpMethod.isSome():
        var foundMain = false
        let
          ctx = req.newContext()
          (path, query) = req.path.unsafeGet().getPathAndQuery()
        extractEncodedParams(query, ctx.queryParams)
        for routeResult in app.router.route(req.httpMethod.unsafeGet(), path, foundMain):
          ctx.pathParams = routeResult.pathParams
          # Run the future then manually handle any error
          var fut = routeResult.handler(ctx)
          yield fut
          if fut.failed:
              when not defined(release):
                stderr.styledWriteLine(
                    fgRed, "Error while handling: ", $req.httpMethod.get(), " ", req.path.get(),
                    "\n" ,fut.error[].msg, "\n", fut.error.getStackTrace(),
                    resetStyle
                )
              ctx.handled = false
              # await handleRequestError(fut.error, ctx)
              # We shouldn't continue after errors so stop processing
              return

        if not foundMain and not ctx.handled:
          ctx.handled = false
          ctx.send(ProblemResponse(
            kind: "NotFoundError",
            detail: path & " could not be found",
            status: Http404
          ))

        elif not ctx.handled:
          # Send response if user set response properties but didn't send
          ctx.send(ctx.response.body, ctx.response.code)

      else:
        req.send("This request is malformed", Http400)
  return onRequest

proc internalMap(mapp; verbs: set[HttpMethod], path: string, position: HandlerPos, handler: Handler) =
  ## Internal function for mapping a handler into the [App]. This is called after a handler
  ## has been transformed via our [placeholdermacro]
  mapp.router.map(verbs, path, handler, position)

macro wrapProc(x: proc): AsyncHandler =
  ## Wraps a proc in context hooks to generate the parameters
  let impl = x.getTypeImpl()
  let
    body = newStmtList()
    innerCall = newCall(x)
    ctxIdent = ident"ctx"

  # Build body from params
  for identDef in impl.params[1 .. ^1]:
    for param in identDef[0 ..< ^2]:
      let ident = ident $param
      innerCall &= newCall(nnkDotExpr.newTree(param, ident"H"), ctxIdent, newLit $param)

  # Build a proc that just calls all the hooks and then calls the original proc
  result = newProc(
    params=[parseExpr"Future[string]", newIdentDefs(ctxIdent, bindSym"Context")],
    pragmas = nnkPragma.newTree(ident"async"),
    body = newStmtList(innerCall)
  )
  echo result.toStrLit

proc map*[P: proc](mapp; verbs: set[HttpMethod], path: string, position: HandlerPos, handler: P) =
  ## Low level function for adding a handler into the router. Handler gets transformed
  ## According to parameters/return
  mapp.internalMap(verbs, path, position, wrapProc(handler))


proc run*(app: var App, port: int = 8080, threads: Natural = 0, bindAddr: string = "0.0.0.0") {.gcsafe.} =
  ## Starts the server, should be called after you have added all your routes
  app.router.rearrange()
  when compileOption("threads"):
    # Use all processors if the user has not specified a number
    let threads = if threads > 0: threads else: countProcessors()

  echo "Started server \\o/ on " & bindAddr & ":" & $port
  let settings = initSettings(
      Port(port),
      bindAddr = bindAddr,
      numThreads = threads
  )
  run(makeOnRequest(app), settings)

