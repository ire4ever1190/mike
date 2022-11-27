import helpers
import common
import context
import std/options
import std/times
import std/strscans
import std/strutils

type
  SameSite* = enum
    Lax
    Strict
    None
  Cookie* = object
    ## Represents the values of a cookie.
    ## Based on the [values here](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie)
    name*, value*: string
    maxAge*: Option[TimeInterval]
    expires*: Option[DateTime]
    domain*, path*: string
    secure*, httpOnly*: bool
    sameSite*: SameSite


func `==`*(a, b: Cookie): bool {.raises: [].} =
  a.name == b.name


proc `$`*(c: Cookie): string {.raises: [].} =
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

proc parseCookies*(value: string): seq[Cookie] =
  ## Parses a cookie. Allows multiple cookies to be passed (They must be seperated by `; `).
  ## Ignores malformed cookies
  for cookie in value.split("; "):
    var newCookie: Cookie
    if cookie.scanf("$+=$*", newCookie.name, newCookie.value):
      result &= newCookie
