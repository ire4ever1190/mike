from context      import AsyncHandler
from std/httpcore import HttpMethod
import router
import macroutils
import httpx
import middleware
import context
import response
import std/[
    macros,
    macrocache,
    asyncdispatch,
    options,
    tables,
    uri,
    strutils,
    strformat
]
##
## ..code-block ::
##      get "/" do:
##          "Hello world"
##


type 
    # This is used has a form of an IR to allow easy adding of pre and post handler
    RouteIR* = ref object 
        preHandlers: seq[AsyncHandler]
        handler: AsyncHandler
        postHandlers: seq[AsyncHandler]
        context: AsyncHandler

    Route = ref object
        handlers: seq[AsyncHandler]
        context: AsyncHandler # This is a closure which which is returned from a proc that knows the correct type. Will be moved to a middleware

    HandlerType* {.pure.} = enum
        Pre
        Middle
        Post

proc joinHandlers(route: RouteIR): seq[AsyncHandler] =
    if route.context != nil:
        result &= move route.context
    result &= move route.preHandlers
    result &= move route.handler
    result &= move route.postHandlers

var
    mikeRouter = newRopeRouter()
    routes: array[HttpMethod, Table[string, RouteIR]]
    patternRoutes: array[HttpMethod, Table[string, RouteIR]] # Used for middlewares that match against multiple routes

const HttpMethods = ["head", "get", "post", "put", "delete", "trace", "options", "connect", "patch"]

proc addHandler(path: string, ctxKind: typedesc, verb: HttpMethod, handType: HandlerType, handler: AsyncHandler) =
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

macro addMiddleware*(path: static[string], verb: static[HttpMethod], handType: static[HandlerType], handler: AsyncHandler) =
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

proc getContextInfo(handler: NimNode): tuple[identifier: NimNode, contextType: NimNode] =
    result.identifier = "ctx".ident()
    result.contextType = "Context".ident()
    if handler.kind == nnkDo: # Only do statement can change the context type
        # For future release I'll need to do a typed macro like in dimscmd
        # to find the implementation of it to see if it extends Context
        if handler.params.len > 1:
            let param = handler.params[1]
            result.identifier = param[0]
            result.contextType = param[1]


template methodHandlerProc(procName, httpMethod, handlerPos) {.dirty.}=
    macro procName*(path: string, handler: untyped) =
        let (contextIdent, contextType) = handler.getContextInfo()
        let body = if handler.kind == nnkStmtList:
                        handler
                    else:
                        handler.body()
        result = quote do:
            addHandler(`path`, `contextType`, HttpMethod(httpMethod), HandlerType(handlerPos)) do (`contextIdent`: `contextType`) -> Future[string] {.gcsafe, async.}:
                `body`

macro addMethodHandlers(): untyped =
    ## Goes through each HttpMethod and adds them
    result = newStmtList()
    for verb in HttpMethod:
        for handlerType in HandlerType:
            # Join before or after if applicable before a lower cased version of the http method name
            let name = ident((case handlerType
                of Pre: "before"
                of Middle: ""
                of Post: "after") & toLowerAscii($verb))

            result.add getAst(methodHandlerProc(name, verb, handlerType))

addMethodHandlers()

include arrowDSL

proc joinPath(parent, child: string): string {.compileTime.} =
    ## Version of join path that works for strings instead of uris
    ## Isn't optimised but it works and only runs at compile time
    for part in parent.split("/") & child.split("/"):
        if part != "":
            result &= "/" & part

func findMethod(input: string): HttpMethod = 
    ## parseEnum is broken on stable so this
    ## basic enum finder is used instead
    for meth in HttpMethod:
        if $meth == input:
            return meth

macro group*(path: static[string], handler: untyped): untyped =
    result = newStmtList()
    var groupRoutes: seq[
        tuple[
            path: string,
            verb: HttpMethod, # the name of the call e.g. `get` or `post`
            call: NimNode, # The full call
        ]
    ]
    var middlewares: seq[
        tuple[
            ident: NimNode,
            position: HandlerType # Pre or Post
        ]
    ]
    for node in handler:
        case node.kind
            of nnkCall, nnkCommand:
                let call = $node[0]
                if call in HttpMethods:

                    var routePath = if node[1].kind == nnkStrLit:
                                    path.joinPath(node[1].strVal())
                                else:
                                    path
                    if node[1].kind != nnkStrLit:
                        # If the node doesn't contain a path then it is just a method handler
                        # for the groups current path
                        node.insert(1, newStrLitNode routePath)
                    # parseEnum is broken on stable
                    # so this basic implementation is used instead
                    # TODO add check if this fails
                    let verb = findMethod(node[0].strVal().toUpperAscii())
                    var call = node
                    call[1] = newStrLitNode routePath
                    groupRoutes &= (path: routePath, verb: verb, call: call)
                elif call == "group":
                    # if node[1].kind != nnkStrLit:
                    #     # If you want to seperate the groups to have middlewares only
                    #     # apply to certain routes then you can do this
                    #     # Probably isn't the cleanest though
                    #     node.insert(1, newStrLitNode path)
                    echo node.treeRepr
                    node[1] = newStrLitNode path.joinPath(node[1].strVal())
                    result &= node
            of nnkIdent:
                middlewares &= (
                    ident: node,
                    position: if groupRoutes.len == 0: Pre else: Post
                )
            else: discard
    for route in groupRoutes:
        let
            path = route.path
            verb = route.verb
        # Add all the middlewares to the route
        for middleware in middlewares:
            let
                position = middleware.position
                ident = middleware.ident
            result.add quote do:
                addMiddleware(
                    `path`,
                    HttpMethod(`verb`),
                    HandlerType(`position`),
                    `ident`
                )
        result &= route.call

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
                let handlers = routeResult.handler
                let ctx = req.newContext(handlers)
                ctx.pathParams = routeResult.pathParams
                ctx.queryParams = routeResult.queryParams

                while ctx.index < ctx.handlers.len():
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
            req.send(body = "how?")



proc addRoutes*(router: var Router[seq[AsyncHandler]], routes: array[HttpMethod, Table[string, RouteIR]]) =
    for verb in HttpMethod:
        for path, route in routes[verb].pairs():
            let handlers = route.joinHandlers()
            router.map(verb, path, handlers)
    router.compress()
    
proc run*(port: int = 8080, threads: int = 0) {.gcsafe.}=
    {.gcsafe.}:
        mikeRouter.addRoutes(routes)
        `=destroy`(routes)
    echo "Started server \\o/ on 127.0.0.1:" & $port
    let settings = initSettings(
        Port(port),
        numThreads = threads
    )
    run(onRequest, settings)
