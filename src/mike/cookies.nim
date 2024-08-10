import helpers
import common
import context
import std/options
import std/times
import std/strscans
import std/strutils
import std/strtabs
import std/uri

##[
  Contains utilities for working with cookies.
  These utilities allow both sending cookies for the client to set and receiving cookies that have be set by the client
]##

runnableExamples:
  # Create a cookie that expires when user closes the browser
  discard initCookie("foo", "bar")

  import std/times
  # Create a cookie that expires after an hour
  discard initCookie("foo", "bar", 1.hours)

  # Create a cookie that expires at a certain date
  discard initCookie("foo", "bar", "2047-11-03".parse("yyyy-MM-dd"))

type
  SameSite* = enum
    ## Controls how cookies are set in cross site requests.
    ## See [MDN docs](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#samesitesamesite-value) for details
    Lax
    Strict
    None

  SetCookie* = object
    ## Represents the values of a cookie.
    ## Based on the [values here](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie).
    ## This is the object you'll be working with when setting cookies in a response
    name*, value*: string
    maxAge*: Option[TimeInterval]
    expires*: Option[DateTime]
    domain*, path*: string
    secure*, httpOnly*: bool
    sameSite*: SameSite


func `==`*(a, b: SetCookie): bool {.raises: [].} =
  ## Two cookies are considered the same if they have the same name
  a.name == b.name

proc `$`*(c: SetCookie): string {.raises: [].} =
  ## Converts the cookie to a string that can be used in headers
  result = c.name & "=" & c.value.encodeUrl()
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

func initCookie*(name, value: string, domain = "", path = "", secure = true,
                httpOnly = false, sameSite = Lax): SetCookie  {.inline, raises: [].}=
  ## Creates a new session cookie, see [MDN Set-Cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie) docs
  ## for explanation about the values
  result = SetCookie(name: name, value: value, domain: domain, path: path,
                     secure: secure, httpOnly: httpOnly, sameSite: sameSite)

func initCookie*(name, value: string, maxAge: TimeInterval, domain = "", path = "", secure = true,
                httpOnly = false, sameSite = Lax): SetCookie {.inline, raises: [].} =
  ## Creates a new cookie that only lasts for a set amount of time
  ##
  ## - See [initCookie][initCookie(name, value, domain, path, secure, httpOnly, sameSite)] for details about parameters
  result = initCookie(name, value, domain, path, secure, httpOnly, sameSite)
  result.maxAge = some maxAge

func initCookie*(name, value: string, expires: DateTime, domain = "", path = "", secure = true,
                httpOnly = false, sameSite = Lax): SetCookie {.inline, raises: [].} =
  ## Creates a new cookie that only lasts until **expires**
  ##
  ## - See [initCookie][initCookie(name, value, domain, path, secure, httpOnly, sameSite)] for details about parameters
  result = initCookie(name, value, domain, path, secure, httpOnly, sameSite)
  result.expires = some expires

proc add*(ctx: Context, c: SetCookie) =
  ## Adds a cookie to the context
  ctx.addHeader("Set-Cookie", $c)

proc parseCookies(value: string, jar: StringTableRef) =
  for cookie in value.split("; "):
    let (ok, key, value) = cookie.scanTuple("$+=$*")
    if ok:
      jar[key] = value.decodeUrl()

proc setCookies*(ctx: Context): StringTableRef =
  ## Returns the cookies that will be sent to the client to be set
  result = newStringTable()
  for header in ctx.getHeaders("Set-Cookie"):
    header.parseCookies(result)

proc cookies*(ctx: Context): StringTableRef =
  ## Returns the cookies that the client has sent
  result = newStringTable()
  for header in ctx.getHeaders("Cookie"):
    header.parseCookies(result)

export strtabs
