import ../context
import httpx
import std/json
import std/jsonutils
import std/options
import std/asyncdispatch
import strtabs

proc body*(ctx: Context): string =
    ## Gets the request body from the request
    ## Returns an empty string if the user sent no body
    ctx.request.body.get("")

proc optBody*(ctx: Context): Option[string] =
    ## Returns the request body from the request
    ctx.request.body

proc hasBody*(ctx: Context): bool =
  ## Returns `true` if the request has a body
  result = ctx.body != ""

proc json*(ctx: Context): JsonNode =
    ## Returns the parsed json
    result = ctx.body.parseJson()

proc json*[T](ctx: Context, to: typedesc[T]): T =
    ## Gets the json from the request and then returns it has a parsed object
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

func pathParam*(ctx: Context, key: string): string =
    ctx.pathParams[key]
