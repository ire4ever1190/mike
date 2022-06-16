import httpcore
import context
import httpx
import strutils
import tables

proc toString*(headers: sink HttpHeaders): string =
  ## Converts HttpHeaders into their correct string representation
  # for header in headers.pairs:
  var first = true
  for key, value in headers.pairs():
    if not first:
      result &= "\c\L"
    first = false
    result &= key
    result &= ": "
    result &= value
    
  # result.strip()
proc respond*(req: Request, ctx: Context) =
    req.send(
        body = ctx.response.body,
        code = ctx.response.code,
        headers = ctx.response.headers.toString()
    )

