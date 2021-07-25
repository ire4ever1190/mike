import ../context
import httpx
import std/json
import std/options
import strtabs

proc body*(ctx: Context): string =
    ## Gets the request body from the request
    ## Returns an empty string if the user sent no body
    ctx.request.body.get("")

proc optBody*(ctx: Context): Option[string] =
    ## Returns the request body from the request
    ctx.request.body

proc json*(ctx: Context): JsonNode =
    ## Returns the parsed json
    result = ctx.body.parseJson()

proc json*[T](ctx: Context, to: typedesc[T]): T =
    ## Gets the json from the request and then returns it has a parsed object
    ctx.json().to(to)

proc getHeader*(ctx: Context, key: string): string =
    ## Gets a header from the request with `key`
    ctx.request.headers.get()[key]

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