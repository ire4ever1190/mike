import ../context
import httpx
import std/json
import std/jsonutils
import std/options
import std/selectors
import std/strformat
import std/strutils
import std/net

import pkg/casserole

{.used.}


proc optBody*(ctx: Context): Option[string] {.inline, raises: [].} =
    ## Returns the request body from the request
    try: ctx.request.body except IOSelectorsException, ValueError: none(string)

proc body*(ctx: Context): string {.inline, raises: [].}=
    ## Gets the request body from the request
    ## Returns an empty string if the user sent no bodyt
    ctx.optBody.get("")

proc hasBody*(ctx: Context): bool {.raises: [].} =
  ## Returns `true` if the request has a body
  result = ctx.body != ""

proc json*(ctx: Context): JsonNode =
    ## Parses JSON from the requests body and returns that
    result = ctx.body.parseJson()

proc json*[T](ctx: Context, to: typedesc[T]): T =
    ## Parses JSON from the requests body and then converts it into `T`
    # TODO: Allow the options to be configured
    result.fromJson(ctx.json(), JOptions(
        allowExtraKeys: true,
        allowMissingKeys: false
    ))

proc headers*(ctx: Context): HttpHeaders {.raises: [].} =
  ## Returns Headers for a request
  try:
    ctx.request.headers.get(newHttpHeaders())
  except KeyError, IOSelectorsException:
    newHttpHeaders()

proc tryGet*(headers: HttpHeaders, key: string): Option[string] =
  ## Attempts to get a header, returns `None` if it doesn't exist
  if headers.hasKey(key):
    return some string(headers[key])

proc tryHeader*(ctx: Context, key: string): Option[string] =
  ## See [tryGet]
  ctx.headers.tryGet(key)

proc getHeader*(ctx: Context, key: string): string =
  ## Gets a header from the request with `key`
  let header = ctx.tryHeader(key)
  if header.isNone():
    raise (ref KeyError)(msg: fmt"Header '{key}' is not in request")
  return header.unsafeGet()

proc getHeaders*(ctx: Context, key: string): seq[string] =
  ## Returns all values for a header. Use this if the request contains multiple
  ## headers with the same key. Returns empty if header doesn't exist
  result = (seq[string])(ctx.headers.getOrDefault(key))

proc getHeader*(ctx: Context, key, default: string): string =
    ## Gets a header from the request with `key` and returns `default`
    ## if it cannot be found
    result = $ctx.headers.getOrDefault(key, @[default].HttpHeaderValues)

proc hasHeader*(ctx: Context, key: string): bool {.raises: [].} =
  ## Returns true if the request has header with `key`
  result = ctx.headers.hasKey(key)

proc ip*(ctx: Context): IpAddress =
  ## Gets the client IP address from the request.
  ## Handles common forwarded headers:
  ## - X-Forwarded-For
  ## - X-Real-IP
  ## - CF-Connecting-IP
  ## - X-Client-IP
  ##
  ## Returns the first (leftmost) IP from forwarded headers,
  ## or falls back to the request's IP address if no forwarded header is present.
  let headers = ctx.headers
  var ipVal
  block finding:
    # First try X-Forwarded-For which has some special parsing
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Forwarded-For
    if Some(forwardedFor) ?== headers.tryGet("X-Forwarded-For"):
      # Return the first
      for ip in forwardedFor.split(','):
        ipVal = ip.strip()
        break finding

    # Next try basic headers that just contain a single IP
    const basicHeaders = ["X-Real-IP", "CF-Connecting-IP", "X-Client-IP"]
    for header in basicHeaders:
      if Some(ip) ?== headers.tryGet(header):
        ipVal = ip
        break finding

    # Just default to the direct IP of whats connecting to us
    ipVal = ctx.request.ip()

  # Now we parse it into an actual IP
  return ipVal.parseAddress()
