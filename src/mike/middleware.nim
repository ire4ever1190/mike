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

proc extendContext*[T: SubContext](ctxType: typedesc[T]): AsyncHandler =
    ## This returns a closure which creates a new object of the users custom type and then moves the current context
    ## into that. It will then runs all the users other handlers
    result = proc (ctx: Context): Future[string] {.gcsafe, closure, async.} =
        var customCtx = new ctxType
        ctx.move(customCtx)
        customCtx.index = 1
        while customCtx.index < customCtx.handlers.len():
            let handler = customCtx.handlers[customCtx.index]
            let response = await handler(customCtx)

            if response != "":
                customCtx.response.body = response

            inc customCtx.index
        customCtx.move(ctx)
