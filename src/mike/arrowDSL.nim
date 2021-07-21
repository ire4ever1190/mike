## This is kept for legacy purposes and will be removed in a later future release
## It is recommended to use the `verb(path) do` syntax

macro `->`*(path: string, contextInfo: untyped, handler: untyped) {.deprecated: "Please use the new syntax (check github for details)".}=
    ## Defines the operator used to create a handler
    runnableExamples:
        "/home" -> get:
            return "You are home"

    let websocketIdent = "ws".ident
    proc getContextInfo(contentInfo: NimNode): tuple[verb: NimNode, contextIdent: NimNode, contextType: NimNode] =
        ## Gets the specified verb along with the context variable and type if specified
        case contentInfo.kind:
            of nnkIdent:
                result.verb = contentInfo
                result.contextIdent = "ctx".ident()
                result.contextType = "Context".ident()
            of nnkObjConstr:
                result.verb = contentInfo[0]
                let colonExpr = contentInfo[1]
                result.contextIdent = colonExpr[0]
                result.contextType = colonExpr[1]
            else:
                raise newException(ValueError, "You have specified a type incorrectly. It should be like `get(ctx: Content)`")

    let (verb, contextIdent, contextType) = contextInfo.getContextInfo()
    result = quote do:
        `verb`(`path`) do (`contextIdent`: `contextType`):
            `handler`
