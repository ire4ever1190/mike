import ../context
import httpx
import std/json
import std/jsonutils
import std/options

{.used.}

proc body*(ctx: Context): string =
    ## Gets the request body from the request
    ## Returns an empty string if the user sent no body
    ctx.request.body.get("")

proc optBody*(ctx: Context): Option[string] =
    ## Returns the request body from the request.
    ## Not really that useful but exists if you want to use it
    ctx.request.body

proc hasBody*(ctx: Context): bool =
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

proc getHeader*(ctx: Context, key: string): string =
    ## Gets a header from the request with `key`
    ctx.request.headers.get()[key]

proc getHeaders*(ctx: Context, key: string): seq[string] =
  ## Returns all values for a header. Use this if the request contains multiple
  ## headers with the same key
  (seq[string])(ctx.request.headers.get()[key])

proc getHeader*(ctx: Context, key, default: string): string =
    ## Gets a header from the request with `key` and returns `default`
    ## if it cannot be found
    let headers = ctx.request.headers
    if headers.isSome:
        result = $headers.get().getOrDefault(key, @[default].HttpHeaderValues):
    else:
        result = default

proc hasHeader*(ctx: Context, key: string): bool =
    ## Returns true if the request has header with `key`
    if ctx.request.headers.isSome:
        result = ctx.request.headers.get().hasKey(key)
