import tables
import macros
import strformat
from router import checkPathCharacters

proc expectKind*(n: NimNode, k: NimNodeKind, msg: string) =
    if n.kind != k:
        error(msg, n)

proc getPath*(handler: NimNode): string =
    ## Gets the path from a DSL adding call
    ## Errors if the node is not a string literal or if it has
    ## illegal characters in it (check router.nim for illegal characters)
    # handler can either be a single strLitNode or an nnkCall with the path
    # as the first node
    let pathNode = if handler.kind == nnkStrLit: handler else: handler[0]
    pathNode.expectKind(nnkStrLit, "The path is not a string literal")
    result = pathNode.strVal
    let (resonable, character) = result.checkPathCharacters()
    if not resonable:
        fmt"Path has illegal character {character}".error(pathNode)

func getHandlerBody(handler: NimNode): NimNode =
    ## Gets the handler body from the different ways that it can be
    ## structured in the handler
    if handler.kind == nnkStmtList:
        # get "/home":
        #     # body
        handler
    else:
        # get("/home") do ():
        #     # body
        handler.body()

## These next few procs are from beef's oopsie library (https://github.com/beef331/oopsie)
## Great library except I needed the code to work on NimNode directly

proc getRefTypeImpl(obj: NimNode): NimNode = obj.getTypeImpl[0].getTypeImpl()

proc superImpl(obj: NimNode): NimNode =
    let impl = obj.getRefTypeImpl
    assert impl[1].kind == nnkOfInherit
    impl[1][0]


proc super*(obj: NimNode): NimNode =
    var obj = obj.getTypeImpl[1].getTypeImpl() # Get the type that is in a typedesc
    if obj.typeKind == ntyRef:
        if not obj.getRefTypeImpl[1][0].eqIdent("RootObj"):
            var sup = obj
            while not sup.getRefTypeImpl[1][0].eqIdent("RootObj"):
                sup = sup.superImpl
            result = sup
        else: result = obj
    else:
        result = obj

proc newHookCall(ctxIdent, kind: NimNode, name: string): NimNode =
    result =
        nnkLetSection.newTree(
            nnkIdentDefs.newTree(
                ident name,
                newEmptyNode(),
                nnkCall.newTree(
                    nnkBracketExpr.newTree(
                        ident "fromContextQuery",
                        ident $kind
                    ),
                    ctxIdent,
                    newLit name
                )
            )
        )

proc createAsyncHandler*(handler: NimNode,
                        parameters: seq[tuple[name: string, kind: NimNode]]): NimNode =
    let body = handler.getHandlerBody()

    let returnType = nnkBracketExpr.newTree(
        newIdentNode("Future"),
        newIdentNode("string")
    )
    var
        ctxIdent = ident "ctx"
        ctxType  = ident "Context"
        hookCalls = newStmtList()
    # Find the context first if it exists
    for parameter in parameters:
        if parameter.kind.super().eqIdent(ctxType):
            ctxIdent = ident parameter.name
            ctxType  = parameter.kind
            break
    # Then add all the calls which require the context
    for parameter in parameters:
        if not parameter.name.eqIdent(ctxIdent):
            hookCalls &= newHookCall(ctxIdent, parameter.kind, parameter.name)
    hookCalls &= body
    result = newProc(
        params = @[
            returnType,
            newIdentDefs(ctxIdent, ctxType)],
        body = hookCalls,
        pragmas = nnkPragma.newTree(
            ident "async"
        )
    )

proc createParamPairs*(handler: NimNode): seq[NimNode] =
    ## Converts the parameters in `handler` into a sequence of name, type, name, type, name, type...
    ## This can then be passed to a varargs[typed] macro to be able to bind the idents for the types
    if handler.kind != nnkStmtList:
        # You can only add parameters when the handler is in the form
        # get("/home") do ():
        #     # body
        for param in handler.params[1..^1]: # Skip return type
            result &= newLit $param[0]
            result &= param[1]

func getParamPairs*(parameters: NimNode): seq[tuple[name: string, kind: NimNode]] =
    ## Gets the parameter pairs (name and type) from a sequence of parameters
    ## where the type follows the name. Expects the name to be a string literal
    ## and the type to be a symbol
    parameters.expectKind(nnkBracket)
    assert parameters.len mod 2 == 0, "Must be even amount of parameters"
    var index = 0
    while index < parameters.len:
        result &= (
            parameters[index].strVal,
            parameters[index + 1]
        )
        index += 2
