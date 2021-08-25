# TODO, change name
import context
import parseutils
import httpcore

type
    ServerError = object of ValueError # TODO, move to seperate file
        response: string # Message sent in response
        code: HttpCode

proc newServerError(msg: string, code: HttpCode): ref ServerError =
    new result
    result.response = msg
    result.code = code

proc fromContextQuery*[T: int](ctx: Context, key: string): int =
    let param = ctx.queryParams[key]
    let L = param.parseInt(result)
    if L != param.len or L == 0:
        raise newServerError("Expected integer, got " & param, Http400)

