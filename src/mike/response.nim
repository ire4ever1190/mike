import httpcore
import context
import httpx
import std/options

proc toString*(headers: sink HttpHeaders): string =
  ## Converts HttpHeaders into their correct string representation
  if headers.len > 0:
    for key, value in headers.pairs():
      result &= key & ": " & value & "\c\L"
    result.setLen(result.len - 2)
    
proc respond*(req: Request, ctx: Context, contentLength = none(int)) =
  ## Responds to a request by sending info back to the client
  req.send(
      body = ctx.response.body,
      code = ctx.response.code,
      contentLength = contentLength,
      headers = ctx.response.headers.toString()
  )
