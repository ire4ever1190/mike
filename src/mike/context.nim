import httpx
import asyncdispatch
import httpcore
import strtabs

type
    Response* = ref object
        code*: HttpCode
        headers*: HttpHeaders
        body*: string
        
    AsyncHandler* = proc (ctx: Context): Future[string] {.gcsafe.}
    #MiddlewareAsyncHandler* = proc (ctx: Context): Future[void]
    
    Context* = ref object of RootObj
        handled*: bool
        response*: Response
        request*: Request
        pathParams*: StringTableRef
        queryParams*: StringTableRef
        handlers*: seq[AsyncHandler] # handlers are stored in the context
        index*: int # The current index in the handlers that is being run

    SubContext* {.explain.} = concept x
        x of Context


proc newResponse*(): Response =
    result = Response(
        code: Http200,
        headers: newHttpHeaders(),
        body: ""
    )
    
proc newContext*(req: Request, handlers: seq[AsyncHandler]): Context =
    result = Context(
        handled: false,
        handlers: handlers,
        response: newResponse(),
        request: req,
        pathParams: newStringTable(),
        queryParams: newStringTable()
    )
