import context

import std/with
import std/asyncdispatch
# I got the idea from
# https://github.com/planety/prologue/blob/devel/src/prologue/core/middlewaresbase.nim


func move(src, ctx: Context) =
    ## move and copies the variables from the source context into the target context
    with ctx:
        handled = src.handled
        index = src.index
        request = move src.request
        handlers = src.handlers
        response = move src.response
        pathParams = move src.pathParams
        queryParams = move src.queryParams

# Old system that I never actually tested
proc extendContext*[T: SubContext](ctxType: typedesc[T]): AsyncHandler =
    result = proc (ctx: Context): Future[string] {.gcsafe, closure, async.} =
        var customCtx = new ctxType
        # var customCtx: ctxType = Context()

        # var customCtx = new Context
        ctx.move(customCtx)
        var i: int = 0
        while i < customCtx.handlers.len():
            let handler = customCtx.handlers[i]
            let response = await handler(customCtx)

            if response != "":
                customCtx.response.body = response

            if customCtx.handled:
                break
            inc customCtx.index
            inc i
        customCtx.move(ctx)
