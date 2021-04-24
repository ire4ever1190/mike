import ../context

import std/httpcore
import std/json

##
## Helpers for working with the response
##

proc `json=`*[T](ctx: Context, json: T) =
    ## Sets response of the context to be the json.
    ## Also sets the content type header
    ## Due to limitations of nim you cannot do
    ##
    ## .. code-block:: nim
    ##    # This is incorrect
    ##    ctx.json = {"hello": "world", "number": 1}
    ##    # But this is correct
    ##    ctx.json = Person(name: "john")
    ctx.response.headers["Content-Type"] = "application/json"
    ctx.response.body = $ %* json