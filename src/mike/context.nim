from httpx import Request
import asyncdispatch
import httpcore
import strtabs

type
    Response = object
        code*: HttpCode
        headers*: HttpHeaders
        body*: string
        
    AsyncHandler* = proc (ctx: Context): Future[string] {.gcsafe.}
    MiddlewareAsyncHandler* = proc (ctx: Context): Future[void]
    
    Context* = ref object of RootObj
        request*: Request
        response*: Response
        pathParams*: StringTableRef
        queryParams*: StringTableRef
        handler: AsyncHandler
        beforeHandler: seq[MiddlewareAsyncHandler]
        afterHandler: seq[MiddlewareAsyncHandler]
        
    
