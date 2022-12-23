import ../context
import httpx
import std/json
import std/jsonutils
import std/options
import strtabs
import std/selectors


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

proc getHeader*(ctx: Context, key: string): string =
    ## Gets a header from the request with `key`
    ctx.request.headers.get()[key]

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

proc httpMethod*(ctx: Context): HttpMethod =
  ## Returns the HTTP method of a request
  # We already check it exists in the onrequest() so we can safely unsafely get it
  ctx.request.httpMethod.unsafeGet()

