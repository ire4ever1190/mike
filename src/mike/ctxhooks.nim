# TODO, change name
import context
import parseutils
import std/tables
import std/parseutils
import httpcore

type
    # code is embedded so that other errors can have a constant code
    ServerError*[code: HttpCode] = object of ValueError ## Generic server error response
        response: string ## Message sent in response

    ParameterNotFound* = object of ServerError[Http400]
    ParameterError*    = object of ServerError[Http400]

    GenericServerError = concept x
        x is ServerError

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

proc fromContextQuery*[T: int](ctx: Context, key: string): int =
    fromContextIntImpl(ctx, key, queryParams)

proc fromContextPath*[T: int](ctx: Context, key: string): string =
    fromContextIntImpl(ctx, key, pathParams)