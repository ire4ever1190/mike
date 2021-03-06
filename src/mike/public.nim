import dsl
import context
import httpcore
import asyncdispatch
import strtabs
import httpx
import nativesockets

proc handleRequest(ctx: Context) {.async.} =
    ctx.response.body = ctx.pathParams["file"] 
    ctx.response.code = Http200
    close ctx.request.client
    
proc setPublic*(path: string) =
    path & "/*file" -> get:
        echo "hello public"
        # await handleRequest(ctx)

