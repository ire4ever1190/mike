from std/httpcore import HttpMethod
import router
import macroutils
import httpx
import context
import response
import common
import helpers/context as contextHelpers
import helpers/response as responseHelpers
import errors

import std/[
    macros,
    asyncdispatch,
    options,
    tables,
    strutils,
    cpuinfo,
    with,
    json,
    strtabs,
    parseutils,
    genasts
]

runnableExamples:
  import mike

  "/" -> get:
    ctx.send("Hello world")


type Route = AsyncHandler

var mikeRouter = Router[Route]()
var errorHandlers: Table[cstring, AsyncHandler]


proc addHandler(path: string, verb: HttpMethod, pos: HandlerPos, handler: AsyncHandler) =
    ## Adds a handler to the routing IR
    mikeRouter.map(verb, path, handler, pos)
      

macro addMiddleware*(path: static[string], verb: static[HttpMethod], pos: static[HandlerPos], handler: AsyncHandler) =
    ## Adds a middleware to a path
    ## `handType` can be either Pre or Post
    ## This is meant for adding plugins using procs, not adding blocks of code
    # This is different from addHandler since this injects a call
    # to get the ctxKind without the user having to explicitly say
    doAssert pos in {Pre, Post}, "Middleware must be pre or post"
    # Get the type of the context parameter

    result = quote do:
        addHandler(`path`, HttpMethod(`verb`), HandlerType(`pos`), `handler`)

macro `->`*(path: static[string], info: untyped, body: untyped): untyped =
    ## Defines the operator used to create a handler
    ## context info is the info about the route e.g. get or get(c: Context)
    let info = getHandlerInfo(path, info, body)
    let handlerProc = createAsyncHandler(body, info.path, info.params)

    result = genAst(path = info.path, meth = info.verb, pos = info.pos, handlerProc):
        addHandler(path, meth, pos, handlerProc)

macro `->`*(error: typedesc[CatchableError], info, body: untyped) =
  ## Used to handle an exception. This is used to override the
  ## default handler which sends a [ProblemResponse](mike/errors.html#ProblemResponse)
  ##
  runnableExamples:
    import mike
    # If a key error is thrown anywhere then this will be called
    KeyError -> thrown:
      ctx.send("The key you provided is invalid")
  #==#
  if info.kind != nnkIdent and not info.eqIdent("thrown"):
    "Verb must be `thrown`".error(info)
  let
    name = $error
    handlerProc = body.createAsyncHandler("/", @[])

  result = nnkAsgn.newTree(
    nnkBracketExpr.newTree(
      bindSym"errorHandlers",
      newLit name
    ),
    handlerProc
  )

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


proc onRequest(req: Request): Future[void] {.async.} =
  {.gcsafe.}:
    if req.path.isSome() and req.httpMethod.isSome():
      var
        found = false
      let ctx = req.newContext()
      let (path, query) = req.path.get().getPathAndQuery()
      extractEncodedParams(query, ctx.queryParams)
      for routeResult in mikeRouter.route(req.httpMethod.get(), path):
        found = true
        ctx.pathParams = routeResult.pathParams
        # Run the future then manually handle any error
        var fut = routeResult.handler(ctx)
        yield fut
        if fut.failed:
          errorHandlers.withValue(fut.error[].name, value):
            discard await value[](ctx)
          do:
            # TODO: Provide catchall to allow overridding default handler?
            #[
              Exception -> thrown:
                ctx.send "Default handler overrridden"
            ]#
            # If user has already provided an error status then use that
            let code = if fut.error[] of HttpError: HttpError(fut.error[]).status
                       elif ctx.status.int in 400..599: ctx.status
                       else: Http400
            ctx.send(ProblemResponse(
              kind: $fut.error[].name,
              detail: fut.error[].msg,
              status: code
            ))
            # We shouldn't continue after errors so stop processing
            return
        else:
          # TODO: Remove the ability to return string. Benchmarker still uses return statement
          # style so guess I'll keep it for some time
          let body = fut.read
          if body != "":
            ctx.response.body = body

      if not found:
        const jsonHeaders = newHttpHeaders({"Content-Type": "application/json"}).toString()
        req.send(body = $ %* ProblemResponse(
          kind: "NotFoundError",
          detail: req.path.get() & " could not be found",
          status: Http404
        ), code = Http404, headers = jsonHeaders)

      elif not ctx.handled:
        # Send response if user set response properties but didn't send
        req.respond(ctx)
          
    else:
      req.send(body = "This request is malformed")




proc run*(port: int = 8080, threads: Natural = 0) {.gcsafe.} =
    ## Starts the server, should be called after you have added all your routes
    {.gcsafe.}:
      mikeRouter.rearrange()
    when compileOption("threads"):
        # Use all processors if the user has not specified a number
        var threads = if threads > 0: threads else: countProcessors()
    echo "Started server \\o/ on 127.0.0.1:" & $port
    let settings = initSettings(
        Port(port),
        numThreads = threads
    )
    run(onRequest, settings)

export asyncdispatch
