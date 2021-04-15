import httpcore
import context
import httpx

proc toString*(headers: HttpHeaders): string =
    ## Converts HttpHeaders into their correct string representation
    for header in headers.pairs:
        result &= header.key & ": " & header.value

proc respond*(req: Request, ctx: Context) =
    req.send(
        body = ctx.response.body,
        code = ctx.response.code,
        headers = ctx.response.headers.toString()
    )

