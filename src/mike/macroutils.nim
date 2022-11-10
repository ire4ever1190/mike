import std/[
  macros,
  strformat,
  httpcore,
  options,
  strutils
]
import router
import common


proc expectKind*(n: NimNode, k: NimNodeKind, msg: string) =
    if n.kind != k:
        error(msg, n)

type
  ProcParameter* = object
    name*: string
    kind*: NimNode
    bodyType*: NimNode

  HandlerInfo* = object
    verb*: HttpMethod
    pos*: HandlerPos
    path*: string
    body*: NimNode
    params*:  seq[ProcParameter]
    pathParams*: seq[string]

proc getVerb(info: NimNode): Option[(HttpMethod, HandlerPos)] =
  ## Parses correct verb from an ident
  for position in [Middle, Pre, Post]:
    for verb in HttpMethod:
      if info.eqIdent($position & toLowerAscii($verb)):
        return some (verb, position)
    
proc getHandlerInfo*(path: string, info, body: NimNode): HandlerInfo =
  ## Gets info about a handler.
  result.path = path
  # Run assert, though it shouldn't be triggered ever since we check this before
  if info.kind notin {nnkIdent, nnkObjConstr, nnkCall}:
    "You have specified a route incorrectly. It should be like `get(<parameters>):` or `get:`".error(info)
  var verbIdent: NimNode
  if info.kind == nnkIdent:
    verbIdent = info
  else:
    verbIdent = info[0]
    # We also need to get the parameters 
    for param in info[1..^1]:
      if param.kind != nnkExprColonExpr:
        "Expect `name: type` for parameter".error(param)
      result.params &= ProcParameter(
        name: param[0].strVal,
        kind: param[1]
      )
        
  # Get the verb from the ident
  let verbInfo = verbIdent.getVerb()
  if verbInfo.isSome:
    let (verb, pos) = verbInfo.get()
    result.verb = verb
    result.pos = pos
  else:
    ("Not a valid route verb `" & $verbIdent & "`").error(verbIdent)
  

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

proc newHookCall(hookname: string, ctxIdent, kind: NimNode, name: string): NimNode =
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
                         path: string,
                         parameters: seq[ProcParameter]): NimNode =
    ## Creates the proc that will be used for a route handler
    let body = handler
    let pathParameters = block:
      var params: seq[string]
      let nodes = path.toNodes()
      for node in nodes:
        if node.kind in {Param, Greedy} and node.val != "":
          params &= node.val
      params
        
    let returnType = nnkBracketExpr.newTree(
        newIdentNode("Future"),
        newIdentNode("string")
    )
    var
        ctxIdent = ident "ctx"
        hookCalls = newStmtList()
    # Find the context first if it exists
    for parameter in parameters:
      if parameter.kind.eqIdent("Context"):
        ctxIdent = ident parameter.name
        break
    # Then add all the calls which require the context
    for parameter in parameters:
        if not parameter.name.eqIdent(ctxIdent):
            if parameter.name in pathParameters:
                hookCalls &= newHookCall("fromPath", ctxident, parameter.kind, parameter.name)
            else:
                hookCalls &= newHookCall("fromForm", ctxIdent, parameter.kind, parameter.name)
    hookCalls &= body
    result = newProc(
        params = @[
            returnType,
            newIdentDefs(ctxIdent, ident "Context")],
        body = hookCalls,
        pragmas = nnkPragma.newTree(
            ident "async",
            ident "gcsafe"
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

func getParamPairs*(parameters: NimNode): seq[ProcParameter] =
    ## Gets the parameter pairs (name and type) from a sequence of parameters
    ## where the type follows the name. Expects the name to be a string literal
    ## and the type to be a symbol
    parameters.expectKind(nnkBracket)
    assert parameters.len mod 2 == 0, "Must be even amount of parameters"
    var index = 0
    while index < parameters.len:
        result &= ProcParameter(
            name: parameters[index].strVal,
            kind: parameters[index + 1]
        )
        index += 2
