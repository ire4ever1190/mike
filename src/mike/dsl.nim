from context      import AsyncHandler
from std/httpcore import HttpMethod
import router
import macroutils
import httpx
import middleware
import context
import response
import common
import std/[
    macros,
    macrocache,
    asyncdispatch,
    options,
    tables,
    uri,
    strutils,
    strformat,
    cpuinfo
]

runnableExamples:
  "/" -> get:
    ctx.send("Hello world")


type 
    # Compile time information about route
    RouteIR* = ref object 
        preHandlers: seq[AsyncHandler]
        handler: AsyncHandler
        postHandlers: seq[AsyncHandler]
        context: AsyncHandler

    # Runtime information about route
    Route = ref object
        handlers: seq[AsyncHandler]
        context: AsyncHandler # This is a closure which which is returned from a proc that knows the correct type. Will be moved to a middleware

proc joinHandlers(route: RouteIR): seq[AsyncHandler] =
    ## Moves all the handlers from the RouteIR into a list of handlers
    if route.context != nil:
        result &= move route.context
    result &= move route.preHandlers
    result &= move route.handler
    result &= move route.postHandlers

var
    mikeRouter = newRopeRouter()
    routes: array[HttpMethod, Table[string, RouteIR]]

const HttpMethods = ["head", "get", "post", "put", "delete", "trace", "options", "connect", "patch"]

# Store all methods that can be handled by the web server
const implementedMethods = [HttpGet, HttpHead, HttpPost, HttpPut, HttpPatch, HttpDelete, HttpOptions]

proc addHandler(path: string, ctxKind: typedesc, verb: HttpMethod, handType: HandlerPos, handler: AsyncHandler) =
    ## Adds a handler to the routing IR
    if not routes[verb].hasKey(path):
      routes[verb][path] = RouteIR(preHandlers: newSeq[AsyncHandler](), postHandlers: newSeq[AsyncHandler]())

    case handType
    of Pre:
      routes[verb][path].preHandlers &= handler
    of Post:
      routes[verb][path].postHandlers &= handler
    of Middle:
      routes[verb][path].handler = handler
      
    if $ctxKind != "Context": # Only a custom ctx needs the extend context closure
      routes[verb][path].context = extendContext(ctxKind)

macro addMiddleware*(path: static[string], verb: static[HttpMethod], handType: static[HandlerPos], handler: AsyncHandler) =
    ## Adds a middleware to a path
    ## `handType` can be either Pre or Post
    ## This is meant for adding plugins using procs, not adding blocks of code
    # This is different from addHandler since this injects a call
    # to get the ctxKind without the user having to explicitly say
    doAssert handType in {Pre, Post}, "Middleware must be pre or post"
    # Get the type of the context parameter
    let ctxKind = ident $handler.getImpl().params[1][1] # Desym the type

    result = quote do:
        addHandler(`path`, `ctxKind`, HttpMethod(`verb`), HandlerType(`handType`), `handler`)


macro createFullHandler*(path: static[string], httpMethod: HttpMethod, handlerPos: HandlerPos,
                         handler: untyped, parameters: varargs[typed] = []): untyped =
    ## Does the needed AST transforms to add needed parsing code to a handler and then
    ## to add that handler to the routing tree. This call also makes the parameters be typed
    ## so that more operations can be performed on them
    let handlerProc = handler.createAsyncHandler(path, parameters.getParamPairs())
    var contextType = ident"Context"
    echo handlerProc.toStrLit
    # Check if custom context type was passed
    for parameter in parameters.getParamPairs():
      if parameter.kind.super().eqIdent("Context"):
        contextType = parameter.kind
        break
    # Now do the final addHandler call to get the generated proc added to the 
    # router
    result = quote do:
        addHandler(`path`, `contextType`, HttpMethod(`httpMethod`), HandlerPos(`handlerPos`), `handlerProc`)
  
macro `->`*(path: static[string], info: untyped, body: untyped): untyped =
    ## Defines the operator used to create a handler
    ## context info is the info about the route e.g. get or get(c: Context)
    runnableExamples:
        "/home" -> get:
            ctx.send "You are home"
    let info = getHandlerInfo(path, info, body)

    # Send the info off to another call to symbol bind the parameters
    result = newCall(
        bindSym "createFullHandler",
        newLit info.path,
        newLit HttpMethod(info.verb),
        newLit HandlerPos(info.pos),
        body
    )
    for param in info.params:
        result &= newLit param.name
        result &= param.kind

template send404() =
    ctx.response.body = "Not Found =("
    ctx.response.code = Http404
    req.respond(ctx) 
    req.send()

proc onRequest(req: Request): Future[void] {.async.} =
    {.gcsafe.}:
        if req.path.isSome() and req.httpMethod.isSome():
            var routeResult = mikeRouter.route(req.httpMethod.get(), req.path.get())
            if likely(routeResult.status):
                let handlers = move routeResult.handler
                let ctx = req.newContext(handlers)
                ctx.pathParams = move routeResult.pathParams
                ctx.queryParams = move routeResult.queryParams

                while ctx.index < ctx.handlers.len:
                    let handler = ctx.handlers[ctx.index]
                    let response = await handler(ctx)

                    if response != "":
                        ctx.response.body = response

                    inc ctx.index

                if not ctx.handled:
                    req.respond(ctx)
                when defined(debug):
                    echo(fmt"{req.httpMethod.get()} {req.path.get()} = {ctx.response.code}")
            else:
                when defined(debug):
                    echo(fmt"{req.httpMethod.get()} {req.path.get()} = 404")
                req.send("Not Found =(", code = Http404)
        else:
            req.send(body = "This request is incorrect")



proc addRoutes*(router: var Router[seq[AsyncHandler]], routes: sink array[HttpMethod, Table[string, RouteIR]]) =
    ## Takes in an array of routes and adds them to the router
    ## it then compresses the router for performance
    for verb in HttpMethod:
        for path, route in routes[verb].pairs():
            let handlers = route.joinHandlers()
            router.map(verb, path, handlers)
    router.compress()


proc run*(port: int = 8080, threads: Natural = 0) {.gcsafe.}=
    {.gcsafe.}:
        mikeRouter.addRoutes(routes)
    when compileOption("threads"):
        # Use all processors if the user has not specified a number
        var threads = if threads > 0: threads else: countProcessors()
    echo "Started server \\o/ on 127.0.0.1:" & $port
    let settings = initSettings(
        Port(port),
        numThreads = threads
    )
    run(onRequest, settings)
