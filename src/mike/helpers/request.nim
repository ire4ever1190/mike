import ../context
import httpx
import std/json
import std/options

proc body*(ctx: Context): string =
    ## Gets the request body from the request
    ## Returns an empty string if the user sent no body
    result = ctx.request.body.get("")

proc json*(ctx: Context): JsonNode =
    ## Returns the parsed json
    result = ctx.body.parseJson()

proc json*[T](ctx: Context, to: typedesc[T]): T =
    ## Gets the json from the request and then returns it has a parsed object
    ctx.json().to(to)

proc header*(ctx: Context, key: string): string =
    ## Gets a header from the request with `key`
    ctx.request.headers.get(newHttpHeaders())[key]

proc hasHeader*(ctx: Context, key: string): bool =
    ## Returns true if the request has header with `key`
    if ctx.request.headers.isSome:
        result = ctx.request.headers.get().hasKey(key)
