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



