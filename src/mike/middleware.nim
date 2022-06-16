import context

import std/with
import std/asyncdispatch
# I got the idea from
# https://github.com/planety/prologue/blob/devel/src/prologue/core/middlewaresbase.nim





proc extendContext*[T: SubContext](ctxType: typedesc[T]): AsyncHandler {.compileTime.} =
    ## This returns a closure which creates a new object of the users custom type and then moves the current context
    ## into that. It will then runs all the users other handlers
    result = proc (ctx: Context): Future[string] {.gcsafe, closure, async.} =
        var customCtx = new ctxType
        ctx.move(customCtx)
        # while customCtx.index < customCtx.handlers.len():
            # let handler = customCtx.handlers[customCtx.index]
            # let response = await handler(customCtx)
# 
            # if unlikely(response != ""):
                # customCtx.response.body = response
# 
            # inc customCtx.index
        # customCtx.move(ctx)

    nil
