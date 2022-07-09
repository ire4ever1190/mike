# TODO, change name
import context
import std/[
  tables,
  parseutils,
  httpcore
]

type
    # code is embedded so that other errors can have a constant code
    ServerError*[code: HttpCode] = object of ValueError ## Generic server error response
        response: string ## Message sent in response

    ParameterNotFound* = object of ServerError[Http400]
    ParameterError*    = object of ServerError[Http400]

    GenericServerError = concept x
        x is ServerError

    Form*[T: object | ref object] = object
    Json*[T: object | ref object] = object

proc newServerError*[T: GenericServerError](msg: string): ref T =
    ## Creates a new server error and sets the response to be `msg`
    new result
    result.response = msg

## TODO, have different errors for missing parameter/invalid parameter

template fromContextIntImpl(ctx: Context, key: string, paramSource: untyped): untyped {.dirty.} =
    bind parseInt
    if ctx.paramSource.hasKey(key):
        let param = ctx.paramSource[key]
        let L = parseInt(param, result)
        if L != param.len or L == 0:
            raise newServerError[ParameterError]("Expected integer, got " & param)
    else:
        raise newServerError[ParameterNotFound]("Expected parameter: " & key)

# proc fromCtx*[T: Form[object]](ctx: Context, t: typedesc[T]): T = discard

# proc fromForm*[T: int](ctx: Context, key: string): int =
    # fromContextIntImpl(ctx, key, queryParams)
# 
# proc fromPath*[T: int](ctx: Context, key: string): string =
    # fromContextIntImpl(ctx, key, pathParams)
