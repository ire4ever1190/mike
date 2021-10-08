import httpx
import asyncdispatch
import httpcore
import strtabs
import std/with

type
    Response* = ref object
        code*: HttpCode
        headers*: HttpHeaders
        body*: string
        
    AsyncHandler* = proc (ctx: Context): Future[string] {.gcsafe.}

    Context* = ref object of RootObj
        handled*: bool
        response*: Response
        request*: Request
        pathParams*: StringTableRef
        queryParams*: StringTableRef
        handlers*: seq[AsyncHandler] # handlers are stored in the context
        index*: int # The current index in the handlers that is being run

    SubContext* = concept x
        x is Context


proc newResponse*(): Response =
    result = Response(
        code: Http200,
        headers: newHttpHeaders(),
        body: ""
    )
    
proc newContext*(req: Request, handlers: seq[AsyncHandler]): Context =
    result = new Context
    with result:
        handled = false
        handlers = handlers
        request = req
        response = newResponse()
        pathParams = newStringTable()
        queryParams = newStringTable()