import ../context
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
    for k, v in child:
        result[k] = v

proc send*(ctx: Context, body: string, code: HttpCode = Http200, extraHeaders: HttpHeaders = newHttpHeaders()) =
    ## Responds to a context
    ctx.response.code = code
    ctx.response.body = body
    ctx.request.send(
        body = ctx.response.body,
        code = ctx.response.code,
        headers = (ctx.response.headers & extraHeaders).toString()
    )
    ctx.handled = true

proc send*[T](ctx: Context, obj: T, code: HttpCode = Http200) =
    ctx.response.headers["Content-Type"] = "application/json"
    ctx.send(
        body = $ %* obj,
        code = code
    )
