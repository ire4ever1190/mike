import httpcore
import context
import httpx
import std/options

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
    
proc respond*(req: Request, ctx: Context, contentLength = none(int)) =
  ## Responds to a request by sending info back to the client
  req.send(
      body = ctx.response.body,
      code = ctx.response.code,
      contentLength = contentLength,
      headers = ctx.response.headers.toString()
  )
