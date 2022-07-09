import httpcore
import context
import httpx

proc toString*(headers: sink HttpHeaders): string =
  ## Converts HttpHeaders into their correct string representation
  var first = true
  for key, value in headers.pairs():
    if not first:
      result &= "\c\L"
    first = false
    result &= key
    result &= ": "
    result &= value
    
proc respond*(req: Request, ctx: Context) =
    req.send(
        body = ctx.response.body,
        code = ctx.response.code,
        headers = ctx.response.headers.toString()
    )

