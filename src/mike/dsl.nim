import router
from context import AsyncHandler
from httpcore import HttpMethod
import macros
import httpx
import middleware
import asyncdispatch
import context
import response
import std/options
import std/tables
import std/uri
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
        context: AsyncHandler # This is a closure which which is returned from a proc that knows the correct type

proc joinHandlers(route: RouteIR): seq[AsyncHandler] =
    result &= move route.preHandlers
    result &= move route.handler
    result &= move route.postHandlers

var mikeRouter = newRouter[Route]()
var routes: array[HttpMethod, Table[string, RouteIR]]

template update(verb: HttpMethod, handlerAttribute: untyped, sequence: bool = false, ctxKind: typedesc[SubContext] = Context) {.dirty.} =
    if not routes[verb].hasKey(path):
        routes[verb][path] = RouteIR(preHandlers: newSeq[AsyncHandler](), postHandlers: newSeq[AsyncHandler]())
    when sequence:
        routes[verb][path].handlerAttribute &= handler
    else:
        routes[verb][path].handler = handler
        routes[verb][path].context = extendContext(ctxKind)

proc get*(path: string, handler: AsyncHandler) =
    # mikeRouter.map(HttpGet, path, handler)
    update(HttpGet, handler)

proc beforeGet*(path: string, handler: AsyncHandler) =
    update(HttpGet, preHandlers, true)

proc post*(path: string, handler: AsyncHandler) =
    # mikeRouter.map(HttpPost, path, handler)
    update(HttpPost, handler)

proc ws*(path: string, handler: AsyncHandler) =
    # mikeRouter.map(HttpGet, path, handler)
    update(HttpGet, handler)

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
    echo contextInfo.getContextInfo()
    var (verb, contextIdent, contextType) = contextInfo.getContextInfo()

    # Add in the websocket code
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
        `verb`(`path`) do (`contextIdent`: `contextType`) -> Future[string] {.gcsafe, async.}:
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
                let route = routeResult.handler
                let ctx = req.newContext(route.handlers)
                ctx.pathParams = routeResult.pathParams
                ctx.queryParams = routeResult.queryParams

                when false:
                    discard await route.context(ctx)
                else:
                    # I am going to be honest
                    # User defined contexts somehow work
                    # I really don't know how they work but they just do
                    # I used to have a complex system with closures but then I found out that it was never even called at it still worked
                    # If someone can explain how it works that would be class
                    for handler in route.handlers:
                        let response = await handler(ctx)
                        if response != "":
                            ctx.response.body = response
                        if ctx.handled: # Stop running routes if a middleware or handler handles the result
                            break
                if not ctx.handled:
                    req.respond(ctx)
            else:
                req.send("Not Found =(", code = Http404)
        else:
            req.send(body = "how?")



proc addRoutes(router: var Router[Route], routes: array[HttpMethod, Table[string, RouteIR]]) =
    for verb in HttpMethod:
        for path, route in routes[verb].pairs():
            let handlers = route.joinHandlers()
            let route = Route(
                handlers: handlers,
                context: move route.context
            )
            router.map(verb, path, route)
    router.compress()
    
proc run*(port: int = 8080, numThreads: int = 0) {.gcsafe.}=
    {.gcsafe.}:
        mikeRouter.addRoutes(routes)
        #`=destroy`(routes)
    echo "Started server on 127.0.0.1:" & $port
    let settings = initSettings(
        Port(port)
    )
    run(onRequest, settings)
