from context      import AsyncHandler
from std/httpcore import HttpMethod
import routers/ropeRouter
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

    HandlerType {.pure.} = enum
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

proc getContextInfo(handler: NimNode): tuple[identifier: NimNode, contextType: NimNode] =
    echo handler.treeRepr
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
            # result &= getAst(basicMethodProc(name, verb, handlerType))
            # TODO clean this before release
            result.add getAst(methodHandlerProc(name, verb, handlerType))

addMethodHandlers()

macro `->`*(path: string, contextInfo: untyped, handler: untyped) {.deprecated: "Please use the new syntax (check github for details)".}=
    ## Defines the operator used to create a handler
    runnableExamples:
        "/home" -> get:
            return "You are home"

    let websocketIdent = "ws".ident
    proc getContextInfo(contentInfo: NimNode): tuple[verb: NimNode, contextIdent: NimNode, contextType: NimNode] =
        ## Gets the specified verb along with the context variable and type if specified
        case contentInfo.kind:
            of nnkIdent:
                result.verb = contentInfo
                result.contextIdent = "ctx".ident()
                result.contextType = "Context".ident()
            of nnkObjConstr:
                result.verb = contentInfo[0]
                let colonExpr = contentInfo[1]
                result.contextIdent = colonExpr[0]
                result.contextType = colonExpr[1]
            else:
                raise newException(ValueError, "You have specified a type incorrectly. It should be like `get(ctx: Content)`")

    let (verb, contextIdent, contextType) = contextInfo.getContextInfo()
    result = quote do:
        `verb`(`path`) do (`contextIdent`: `contextType`):
            `handler`

macro group*(path: string, handler: untyped): untyped =
    echo handler.treeRepr
    for node in handler:
        case node.kind
            of nnkCall:
                discard
            else: discard

type TempHandler = object
    path: string
    verb: NimNode
    body: NimNode

proc joinPath(a, b: string): string =
    var a = a
    var b = b
    if a[0] != '/':
        a.insert("/", 0)
    a.removeSuffix('/')
    b.removePrefix('/')
    result = a & '/' & b


# proc parseComplexDSL(path: string, section: NimNode, routes, preHandlers, postHandlers: seq[TempHandler]): NimNode =
    # echo path
    # var paths: seq[string]
    # for node in section:
        # echo node.astGenRepr
        # var nextPath = ""
        # if (node.kind == nnkCall and node[0].kind == nnkStrLit):
            # nextPath = path.joinPath(node[0].strVal)
        # elif (node.kind == nnkInfix and node[1].kind == nnkStrLit):
            # nextPath = path.join(node[1].strVal)
        # if nextPath != "":
            # paths &= nextPath
    # for path in paths:
        # discard parseComplexDSL(nextPath, node[1], newSeq[TempHandler](), newSeq[TempHandler](), newSeq[TempHandler]())
    # return newStmtList()
    # echo section.astGenRepr()

# macro group*(startingPath: static[string], routes: varargs[untyped]): untyped =
    # echo startingPath
    # result = parseComplexDSL(startingPath, routes[0], newSeq[TempHandler](), newSeq[TempHandler](), newSeq[TempHandler]())
    # echo result.toStrLit()

template send404() =
    ctx.response.body = "Not Found =("
    ctx.response.code = Http404
    req.respond(ctx) 
    req.send()

proc onRequest(req: Request): Future[void] {.async.} =
    {.gcsafe.}:
        if req.path.isSome() and req.httpMethod.isSome():
            var routeResult = mikeRouter.route(req.httpMethod.get(), req.path.get())
            if routeResult.status:
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
