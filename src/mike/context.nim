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

    SubContext* = concept x
        x is Context


proc newResponse*(): Response =
    result = Response(
        code: Http200,
        headers: newHttpHeaders(),
        body: ""
    )
    
proc newContext*(req: Request): Context =
    result = new Context
    with result:
      handled = false
      request = req
      response = newResponse()
      pathParams = newStringTable()
      queryParams = newStringTable()
