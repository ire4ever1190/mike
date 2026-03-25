## This module configures [CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS).
## This is needed when a site on a different domain/port needs to connect to the server (e.g. frontend running on a different port)

import ../[app, context, errors, common, helpers, ctxhooks]

import std/[asyncdispatch, sugar, httpcore, setutils, times, strutils, options, strformat]

import pkg/casserole

export times

const
  allowAll* = ["*"]
    ## Pass to a parameter to allow for anything (e.g. all hosts)
  allMethods* = fullSet(HttpMethod)
    ## Pass to allow for all methods to be used

proc matchedOrigin*(origins: openArray[string], origin: string): Option[string] =
  ## Checks if an `origin` matches in a list of `origins`.
  ## Must either match an origin exactly (schema, host, port) or match `"*"`
  for expected in origins:
    if expected == "*" or origin == expected:
      return some origin

proc inSeconds(interval: TimeInterval): float64 =
  ## Converts from interval to a unit.
  ## Slightly useful, move into helper lib and generalise?
  let parts = interval.toParts()
  # Check nothing unsupported
  for unit in [Months, Years]:
    if parts[unit] != 0:
      raise (ref ValueError)(msg: fmt"Cannot use {unit} since conversion is not constant")
  const conversion = block:
    let values: array[Nanoseconds..Weeks, float64] = [
      1e-9,
      1e-6,
      1e-3,
      1,
      60,
      60 * 60,
      60 * 60 * 24,
      60 * 60 * 24 * 7
    ]
    values
  for unit in Nanoseconds..Weeks:
    result += parts[unit].float64 * conversion[unit]

proc addCORS*(
  app: var App,
  origins: openArray[string] = allowAll,
  methods: set[HttpMethod] = allMethods,
  headers: openArray[string] = [],
  credentials: bool = false,
  exposeHeaders: openArray[string] = [],
  maxAge: TimeInterval = 5.minutes
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
  runnableExamples:
    import mike

    var app = initApp()
    app.addCORS(
      # Origins we want to access from e.g. a JS dev server
      origins = ["http://localhost:8080", "http://127.0.0.1:8080"],
      methods = allMethods,
      # Allow cookies to be sent
      credentials = true,
      # Add any custom headers here you want the client to be able to send to the server
      headers = ["X-Foo"],
      # Add any custom headers here that you want the client to be able to receive from the server
      exposeHeaders = ["X-Bar"]
    )

  assert origins.len > 0, "origins must not be empty"

  let
    origins = @origins
    # Prejoin some of the values for performance
    allowedHeaders = headers.join(", ")
    exposedHeaders = exposeHeaders.join(", ")
    fullAllowedMethods = methods + {HttpOptions} # We allow options also so they can preflight
    allowedMethods = collect(for meth in fullAllowedMethods: $meth).join(", ")

  # For simple requests, we just have a middleware
  app.map(fullAllowedMethods, "/^_", HandlerPos.Pre) do (origin: Header[string], ctx: Context):
    ctx.status = Http200

    if Some(matched) ?== origins.matchedOrigin(origin):
      # If it matches, send that host back (Needed for credentials, host must match exactly).
      # Sending nothing back is clear enough to the client that they are not allowed
      ctx.setHeader("Access-Control-Allow-Origin", matched)

    ctx.setHeader("Vary", "Origin") # So client knows we give different response for different hosts
    if credentials:
      ctx.setHeader("Access-Control-Allow-Credentials", "true")

    if exposedHeaders != "":
      ctx.setHeader("Access-Control-Expose-Headers", exposedHeaders)

  # Preflight requests add a bit extra on top to handle headers and methods
  app.options("/^_") do (ctx: Context):
    # Preflight only headers, not needed for simple requests
    if allowedHeaders != "":
      ctx.setHeader("Access-Control-Allow-Headers", allowedHeaders)
    if allowedMethods != "":
      ctx.setHeader("Access-Control-Allow-Methods", allowedMethods)
    ctx.setHeader("Access-Control-Max-Age", $int(maxAge.inSeconds()))
