import router
from context import AsyncHandler
import httpx
import middleware
import context
import response
import std/macros
import std/asyncdispatch
import std/options
import std/tables
import std/uri
import std/strutils
import std/strformat
from std/httpcore import HttpMethod   
##
## ..code-block ::
##      get "/" do:
##          "Hello world"


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

proc joinHandlers(route: RouteIR): seq[AsyncHandler] =
    if route.context != nil:
        result &= move route.context
    result &= move route.preHandlers
    result &= move route.handler
    result &= move route.postHandlers

var mikeRouter = newRouter[seq[AsyncHandler]]()
var routes {.compileTime.}: array[HttpMethod, Table[string, RouteIR]]

proc update(path: string, verb: HttpMethod, handler: AsyncHandler, before = false, sequence = false, ctxKind: typedesc[SubContext] = Context) =
    if not routes[verb].hasKey(path):
        routes[verb][path] = RouteIR(preHandlers: newSeq[AsyncHandler](), postHandlers: newSeq[AsyncHandler]())
    if sequence:
        if before:
            routes[verb][path].preHandlers &= handler
        else:
            routes[verb][path].postHandlers &= handler
    else:
        routes[verb][path].handler = handler

    if $ctxKind != "Context": # Only a custom ctx needs the extend context closure
        routes[verb][path].context = extendContext(ctxKind)

template methodHandlers(preProcName, procName, postProcName: untyped, httpMethod: HttpMethod) =
    ## This template generates the procs for pre/post and normal handler for a specified httpMethod
    proc procName*(path: string, ctxKind: typedesc, handler: AsyncHandler) =
        update(path, HttpMethod(httpMethod), handler, ctxKind = ctxKind)

    proc `preProcName`*(path: string, ctxKind: typedesc, handler: AsyncHandler) =
        update(path, HttpMethod(httpMethod), handler, before = true, sequence = true, ctxKind = ctxKind)

    proc `postProcName`*(path: string, ctxKind: typedesc, handler: AsyncHandler) =
        update(path, HttpMethod(httpMethod), handler, before = false, sequence = true, ctxKind = ctxKind)

macro addMethodHandlers(): untyped =
    ## Goes through each HttpMethod and adds them
    result = newStmtList()
    for verb in HttpMethod:
        let
            before = ident("before" & $verb)
            middle = toLowerAscii($verb).ident()
            after = ident("after" & $verb)
        result &= getAst(methodHandlers(before, middle, after, verb))

addMethodHandlers()

proc ws*(path: string, ctxKind: typedesc, handler: AsyncHandler) =
    update(path, HttpGet, handler, ctxKind = ctxKind)

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

macro `->`*(path: string, contextInfo: untyped, handler: untyped) =
    ## Defines the operator used to create a handler
    runnableExamples:
        "/home" -> get:
            return "You are home"
                        
    let websocketIdent = "ws".ident
    let (verb, contextIdent, contextType) = contextInfo.getContextInfo()

    let webSocketCode = if verb == "ws".ident:
            quote do:
                var `webSocketIdent`: WebSocket
                try:
                    `websocketIdent` = await newWebSocket(`contextIdent`.request)
                except:
                    `contextIdent`.handled = true
                    `contextIdent`.request.send(Http404)
                    return
        else:
            newStmtList()
    
    result = quote do:
        `verb`(`path`, `contextType`) do (`contextIdent`: `contextType`) -> Future[string] {.gcsafe, async.}:
            `webSocketCode`
            `handler`

template send404() =
    ctx.response.body = "Not Found =("
    ctx.response.code = Http404
    req.respond(ctx) 
    req.send()

proc onRequest(req: Request): Future[void] {.async.} =
    {.gcsafe.}:
        if req.path.isSome() and req.httpMethod.isSome():
            var routeResult = mikeRouter.route(req.httpMethod.get(), req.path.get().parseURI())
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
                    echo(fmt"{req.httpMethod.get()} {req.path.get()} = {Http404}")
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