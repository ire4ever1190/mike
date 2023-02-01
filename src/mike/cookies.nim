import helpers
import common
import context
import std/options
import std/times
import std/strscans
import std/strutils
import std/strtabs

type
  SameSite* = enum
    Lax
    Strict
    None

  SetCookie* = object
    ## Represents the values of a cookie.
    ## Based on the [values here](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-SetCookie).
    ## This is the object you'll be working with when setting cookies in a response
    name*, value*: string
    maxAge*: Option[TimeInterval]
    expires*: Option[DateTime]
    domain*, path*: string
    secure*, httpOnly*: bool
    sameSite*: SameSite


func `==`*(a, b: SetCookie): bool {.raises: [].} =
  a.name == b.name


proc `$`*(c: SetCookie): string {.raises: [].} =
  ## Converts the cookie to a string that can be used in headers
  result = c.name & "=" & c.value
  if c.maxAge.isSome():
    let currentTime = now()
    # Bit hacky, but easiest way to convert interval to seconds
    let seconds = (currentTime + c.maxAge.unsafeGet() - currentTime).inSeconds()
    result &= "; Max-Age=" & $seconds
  elif c.expires.isSome():
    result &= "; Expires=" & c.expires.unsafeGet().format(httpDateFormat)
  if c.domain != "":
    result &= "; Domain=" & c.domain
  if c.path != "":
    result &= "; Path=" & c.path
  if c.secure: result &= "; Secure"
  if c.httpOnly: result &= "; HttpOnly"
  result &= "; SameSite=" & $c.sameSite

proc parseSetCookies(value: string, jar: StringTableRef) =
  ## Internal proc that does the decoding. Better than needing
  ## to make a new table for each cookie header and joining them
  for cookie in value.split("; "):
    let (ok, key, value) = cookie.scanTuple("$+=$*")
    if ok:
      jar[key] = value

proc parseSetCookies(value: string): StringTableRef =
  ## Parses a cookie. Allows multiple cookies to be passed (They must be seperated by `; `).
  ## Ignores malformed cookies
  result = newStringTable()
  value.parseSetCookies(result)

proc parseCookies(value: string, jar: StringTableRef) =
  for cookie in value.split("; "):
    let (ok, key, value) = cookie.scanTuple("$+=$*")
    if ok:
      jar[key] = value

proc setCookies*(ctx: Context): StringTableRef =
  ## Returns the cookies that will be sent to the client to be set
  result = newStringTable()
  for header in ctx.getHeaders("SetCookie"):
    header.parseSetCookies(result)

proc cookies*(ctx: Context): StringTableRef =
  ## Returns the cookies that the client has sent
  result = newStringTable()
  for header in ctx.getHeaders("Cookie"):
    header.parseCookies(result)

export strtabs
