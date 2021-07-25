import ../context
import std/json
import std/httpcore
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

proc send*[T](ctx: Context, obj: T, code: HttpCode = Http200, extraHeaders: HttpHeaders = nil) =
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