## This module configures [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS).
## This is needed when a site on a different domain/port needs to connect to the server (e.g. frontend running on a different port)

import ../[app, context, errors]
import ../helpers/request

import std/[asyncdispatch, uri, httpcore, setutils, times, sets]

import pkg/casserole

const
  allowAll* = ["*"]
    ## Pass to a parameter to allow for anything (e.g. all hosts)
  allMethods* = fullSet(HttpMethod)
    ## Pass to allow for all methods to be used

# Define some headers so I don't misspell
const
  origin = "Origin"
  allowOrigin = "Access-Control-Allow-Origin"

proc matchedOrigin*(origins: openArray[string], origin: string): Option[string] =
  ## Checks if an `origin` matches in a list of `origins`.
  ## Must either match an origin exactly (schema, host, port) or match `"*"`
  for expected in origins:
    if expected == "*" or origin == expected:
      return true

proc addCors*(
  app: var App,
  origins: openArray[string] = allowAll,
  methods: set[HttpMethod] = allMethods,
  headers: openArray[string] = [],
  credentials: bool = false,
  exposeHeaders: openArray[string] = [],
  maxAge: Duration = 5.minutes
  ) =
  ## Configures CORs for the app. This handles both
  ## - [Preflight Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS#preflighted_requests)
  ## - [Simple Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS#simple_requests)
  ##
  ## **Params**
  ## - `origins`: List of hosts (e.g. `https://google.com`) that are allowed to access resources.
  ##              Fixed origins must be set if you want to use credentials.
  ##              See [Access-Control-Allow-Origin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS#access-control-allow-origin)
  ## - `methods`: List of methods to allow. See [Access-Control-Allow-Methods](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS#access-control-allow-methods)
  ## - `headers`: List of headers to allow the client to send in a cross origin request. See [Access-Control-Allow-Headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS#access-control-allow-methods)
  ## - `credentials`: Allows cookies to be sent for cross origin requests.
  ##                  Note: This will allow credentials even if the origins allow from all.
  ##                  See [Access-Control-Allow-Credentials](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS#access-control-allow-credentials)
  ## - `exposeHeaders`: Exposes headers so that the client can read them from the response. See [Access-Control-Expose-Headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS#access-control-expose-headers)
  ## - `maxAge`: How long the browser should cache the preflight request. See [Access-Control-Max-Age](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS#access-control-max-age)
  assert origins.len > 0, "origins must not be empty"

  let
    origins = @origins
    # Prejoin some of the values for performance
    allowedHeaders = headers.join(", ")
    exposedHeaders = exposeHeaders.join(", ")
    allowedMethods = collect(for meth in methods: $meth).join(", ")

  # For simplicity we handle both simple and preflight requests together
  app.map(methods, "/^_", HandlerPos.Pre) do (ctx: Context) {.async.}:
    let sentOrigin = ctx.tryHeader(origin).get("")
    if Some(matched) ?== origins.matchedOrigin(sentOrigin):
      # If it matches, send that host back (Needed for credentials, host must match exactly)
      ctx.setHeader(allowOrigin, originVal)
    else:
      # Give it some other host so the client knows it failed the check
      ctx.setHeader(allowOrigin, origins[0])

    ctx.setHeader("Vary", "Origin") # So client knows we give different response for different hosts
    if credentials:
      ctx.setHeader("Access-Control-Allow-Credentials", "true")

    # These are the same every request
    ctx.setHeader("Access-Control-Allow-Headers", allowedHeaders)
    ctx.setHeader("Access-Control-Allow-Methods", allowedMethods)
    ctx.setHeader("Access-Control-Expose-Headers", exposedHeaders)
    ctx.setHeader("Access-Control-Max-Age", maxAge.inSeconds)
