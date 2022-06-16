import ../context
import std/json
import std/httpcore
import std/os
##
## Helpers for working with the context
##

proc toString(headers: HttpHeaders): string =
    ## Converts HttpHeaders into their correct string representation
    for header in headers.pairs:
        result &= header.key & ": " & header.value

proc `&`(parent, child: HttpHeaders): HttpHeaders =
    ## Merges the child headers with the parent headers and returns them has a new header
    result = parent
    if child != nil:
        for k, v in child:
            result[k] = v

proc send*(ctx: Context, body: string, code: HttpCode, extraHeaders: HttpHeaders = nil) =
    ## Responds to a context and overwrites the status code
    ctx.response.code = code
    ctx.response.body = body
    ctx.request.send(
        body = ctx.response.body,
        code = ctx.response.code,
        headers = (ctx.response.headers & extraHeaders).toString()
    )
    ctx.handled = true

proc send*[T](ctx: Context, obj: T, code = Http200, extraHeaders: HttpHeaders = nil) =
    ## Responds to a context in json format with obj T
    ## automatically sets the `Content-Type` header to "application/json"
    ctx.response.headers["Content-Type"] = "application/json"
    ctx.send(
        body = $ %* obj,
        code,
        extraHeaders = extraHeaders
    )

proc send*(ctx: Context, body: string, extraHeaders: HttpHeaders = nil) =
    ## Responds to a context with `body` and does not overwrite
    ## the current status code
    ctx.send(
        body,
        ctx.response.code,
        extraHeaders = extraHeaders
    )

const maxReadAllBytes {.strdefine.} = 10_000_000 # Max size in bytes before buffer reading

proc sendFile*(ctx: Context, filename: string, dir = ".", headers: HttpHeaders = nil,
               downloadName = "", charset = "utf-8", bufsize = 4096) {.async.} =
    ## Responds to a context with a file
    # Implementation was based on staticFileResponse in https://github.com/planety/prologue/blob/devel/src/prologue/core/context.nim
    let filePath = dir / filename
    if not filePath.fileExists:
        ctx.send(filename & " cannot be found", Http404)
        return
    if fpUserRead notin filename.getFilePermissions():
        ctx.send("You are unauthorised to access this file", Http403)
        return
    let
        info = getFileInfo(filePath)
        contentLength = info.size
        lastModified = info.lastWriteTime
    # if contentLength < maxReadAllBytes:
    ctx.send(filePath.readFile())

