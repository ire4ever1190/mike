import router, context, common, errors, ctxhooks, dispatchTable, pragmas, macroutils
import helpers

import std/[httpcore, macros, options, asyncdispatch, parseutils, strtabs, terminal, cpuinfo, sugar, strutils]

import httpx

## This is a fully typesafe version of the API. All responses should be
## done by returning like a normal function. For getting data, [Context]
## can be used by using context hooks is strongly encouraged

# TODO Support future returns, better extraction like `createASyncHandler`
# TODO Support implicit path parameters

type
  Handler* = AsyncHandler
  ErrorHookHandler* = proc (ctx: Context, error: Exception) {.async, gcsafe.}
  LifeCycleHooks = object
    beforeEach, afterEach: seq[Handler]
    onError: seq[ErrorHookHandler]

  App* = object
    ## Entrypoint for a Mike application.
    ## All routes get registered to this
    router: Router[AsyncHandler]
      ## Routes requests to their handlers
    errorDispatcher: DispatchTable[ref Exception, Context, Future[void]]
      ## Dispatch table for handling errors in handlers
    hooks: LifeCycleHooks
      ## Hooks that are invoked during the lifecycle of every request. This is
      ## meant for global middlewares e.g. logging

using mapp: var App

func noAsyncMsg(input: sink string): string {.inline.} =
  ## Removes the async traceback from a message
  discard input.parseUntil(result, "\nAsync traceback:")

proc defaultExceptionHandler(error: ref Exception, ctx: Context) {.async.} =
  ## Base handler for handling errors
  # If user has already provided an error status then use that
  let code = if error[] of HttpError: HttpError(error[]).status
             elif ctx.status.int in 400..599: ctx.status
             else: Http400
  # Send the details
  ctx.send(ProblemResponse(
    kind: $error[].name,
    detail: error[].msg.noAsyncMsg(),
    status: code
  ), code)

proc handle*[E: Exception](mapp; err: typedesc[E], handler: DispatchMethod[ref E, Context, Future[void]]) =
  ## Adds an exception handler to the app. This handler is then called whenever the exception
  ## is raised when handling a route
  mapp.errorDispatcher.add(ref E, handler)

proc beforeEach*(mapp; handler: Handler) =
  ## Handler that runs before every request
  mapp.hooks.beforeEach &= handler

proc afterEach*(mapp; handler: Handler) =
  ## Handler that runs after every request
  mapp.hooks.afterEach &= handler

proc onError*(mapp; handler: ErrorHookHandler) =
  ## Called whenever an error occurs. This should not be used for handling requests but
  ## for just logging info. Use [handle] for handling exceptions
  mapp.hooks.onError &= handler

proc initApp*(): App =
  ## Creates a new Mike app.
  result = App()
  result.handle(Exception, defaultExceptionHandler)

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
      if req.path.isNone() or req.httpMethod.isNone():
        req.send("This request is malformed", Http400)
        return

      # Get intial data from the request. Build our internal context object
      let
        ctx = req.newContext()
        (path, query) = req.path.unsafeGet().getPathAndQuery()
      extractEncodedParams(query, ctx.queryParams)

      # Go through every possible route and find the ones that match. We need
      # to track if main is found so that we know if the main handler has ran or not
      var foundMain = false
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
          await app.errorDispatcher.call(fut.error, ctx)
          # We shouldn't continue after errors so stop processing
          return

      # Run default 404 handler and drain the context if needed
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

  return onRequest

proc internalMap(mapp; verbs: set[HttpMethod], path: string, position: HandlerPos, handler: Handler) =
  ## Internal function for mapping a handler into the [App]. This is called after a handler
  ## has been transformed via our [placeholdermacro]
  mapp.router.map(verbs, path, handler, position)

import std/typetraits

template trySendResponse(ctx: Context, response: untyped): untyped =
  ## Calls a [sendResponse] hook if the handler hasn't already sent a response
  when typeof(response) is void:
    # Make sure handler is still called
    response
  else:
    let resp = response
  if not ctx.handled:
    when typeof(response) isnot void:
      ctx.sendResponse(when typeof(response) is Future: await resp else: resp)

proc getParam(x: NimNode, name: string): NimNode =
  ## Finds the parameter with a certain name
  for identDef in x.params[1 .. ^1]:
    for param in identDef[0 ..< ^2]:
      if param.skip({nnkPragmaExpr}).eqIdent(name):
        return nnkIdentDefs.newTree(param, identDef[^2], newEmptyNode())

macro wrapProc(path: static[string], x: proc): AsyncHandler =
  ## Wraps a proc in context hooks to generate the parameters.
  ## Path is required to generate implicit path parameters
  let impl = x.getTypeImpl()
  let
    body = newStmtList()
    innerCall = newCall(x)
    ctxIdent = ident"ctx"
    pathNames = getParamNames(path)
    vars = nnkVarSection.newTree()
  echo x.getTypeImpl().treeRepr
  let prc = if x.kind in RoutineNodes: x else: x.getImpl()
  # Build body from params using the type since its easier to navigate
  for identDef in impl.params[1 .. ^1]:
    for param in identDef[0 ..< ^2]:
      var typ = identDef[^2]
      # Automatically mark variables that appear in the path as Path
      if $param in pathNames:
        typ = nnkBracketExpr.newTree(bindSym"Path", typ)

      # Remove `var` from types
      if typ.kind == nnkVarTy:
        typ = typ[0]

      # Add a variable that the call will fill
      let varSym = genSym(nskVar, $param)
      vars &= newIdentDefs(varSym, typ)

      innerCall &= varSym

      # Check if the `name` pragma is used by the param, and use that instead
      let paramNode = prc.getParam($param)
      let namePragma =  paramNode[0].getPragmaNodes().getPragma(bindSym("name"))
      let name = namePragma.map(it => it[1]).get(newLit $param)

      body &= newCall(bindSym"getCtxHook", typ, ctxIdent, name, varSym)

  # Build a proc that just calls all the hooks and then calls the original proc
  result = newProc(
    params=[newEmptyNode(), newIdentDefs(ctxIdent, bindSym"Context")],
    pragmas = nnkPragma.newTree(ident"async"),
    body = newStmtList(
      vars,
      body,
      newCall(bindSym"trySendResponse", ctxIdent, innerCall)
    )
  )

template map*[P: proc](mapp; verbs: set[HttpMethod], path: static[string], position: HandlerPos, handler: P) =
  ## Low level function for adding a handler into the router. Handler gets transformed
  ## According to parameters/return
  mapp.internalMap(verbs, path, position, wrapProc(path, handler))

template map*(mapp; verbs: set[HttpMethod], path: static[string], position: HandlerPos, handler: AsyncHandler) =
  ## Optimised version of `map` that doesn't wrap the proc since its already an [AsyncHandler]
  mapp.internalMap(verbs, path, position, handler)

template map*[P: proc](mapp; verbs: set[HttpMethod], path: static[string], handler: P) =
  ## Like [map(mapp, verbs, path, position, handler)] except it defaults to a normal handler
  mapp.map(verbs, path, Middle, handler)

macro addHelperMappers(): untyped =
  ## Generates mappings to map routes easier e.g. `http.get(...)` instead of `http.map(...)`
  result = newStmtList()
  for position in HandlerPos:
    for meth in HttpMethod:
      let methName = if position == Middle: toLowerAscii($meth) else: toLowerAscii($meth).capitalizeAscii()
      let name = ident($position & methName)
      result.add quote do:
        template `name`*(mapp; path: static[string], handler: proc) =
          mapp.map({`meth`}, path, `position`, handler)
  echo result.toStrLit
addHelperMappers()

proc setup(app: var App, port: int, threads: Natural, bindAddr: string): Settings =
  ## Performs setup for the app. Returns settings that can be used to start it
  app.router.rearrange()
  when compileOption("threads"):
    # Use all processors if the user has not specified a number
    let threads = if threads > 0: threads else: countProcessors()

  echo "Started server \\o/ on " & bindAddr & ":" & $port
  return initSettings(
      Port(port),
      bindAddr = bindAddr,
      numThreads = threads
  )

proc run*(app: var App, port: int = 8080, threads: Natural = 0, bindAddr: string = "0.0.0.0") {.gcsafe.} =
  ## Starts the server, should be called after you have added all your routes
  let settings = app.setup(port, threads, bindAddr)
  run(makeOnRequest(app), settings)

proc runAsync*(app: var App, port: int = 8080, threads: Natural = 0, bindAddr: string = "0.0.0.0"): Future[void] {.gcsafe.} =
  ## Starts the server in the background, useful for spawning a test server or integration with other async procs
  let settings = app.setup(port, threads, bindAddr)
  runAsync(makeOnRequest(app), settings)


export ctxhooks
