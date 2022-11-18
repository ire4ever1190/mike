import std/[
  macros,
  strformat,
  httpcore,
  options,
  strutils,
  tables
]
import router
import common
import ctxhooks
from context import Context
import std/genasts


proc expectKind*(n: NimNode, k: NimNodeKind, msg: string) =
    if n.kind != k:
        error(msg, n)

type
  ProcParameter* = object
    name*: string
    kind*: NimNode
    bodyType*: NimNode
    pragmas*: Table[string, NimNode]

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
    # We also need to get the parameters. Since we are
    # working with a command tree we need to manually convert a, b: string into a: string, b: string
    # using a stack
    var paramStack: seq[ProcParameter]
    for param in info[1..^1]:
      case param.kind
      of nnkExprColonExpr: # Add type info to stack of paramters
        if param[0].kind == nnkPragmaExpr:
          var item = ProcParameter(name: param[0][0].strVal)
          for pragma in param[0][1]:
            item.pragmas[pragma[0].strVal.nimIdentNormalize] = pragma[1]
          paramStack &= item
        else:
          paramStack &= ProcParameter(name: param[0].strVal)
        for item in paramStack.mitems:
          item.kind = param[1]
          result.params &= item
        paramStack.setLen(0)
      of nnkIdent: # Add another parameter
        paramStack &= ProcParameter(name: param.strVal)
      of nnkPragmaExpr: # Add another prameter + its pragmas
        var item = ProcParameter(name: param[0].strVal)
        for pragma in param[1]:
          item.pragmas[pragma[0].strVal.nimIdentNormalize] = pragma[1]
        paramStack &= item
      else:
        echo param.treeRepr
        "Expects `name: type` for parameter".error(param)


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
        ident"Future",
        ident"string"
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
    for par in parameters:
        if not par.name.eqIdent(ctxIdent):
            # Get the name, it might be changed with a pragma
            let name = if "name" in par.pragmas:
                let namePragma = par.pragmas["name"]
                if namePragma.kind != nnkStrLit:
                  "Name must be a string".error(namePragma)
                namePragma.strVal
              else:
                par.name
            # If its in the path then automatically add Path type
            # Check if we can automatically add the Path annotation or not
            # Make sure we don't add it twice i.e. Path[Path[T]]
            let paramKind = if name in pathParameters and
                               (par.kind.kind == nnkIdent or not par.kind[0].eqIdent("Path")):
                nnkBracketExpr.newTree(bindSym"Path", par.kind)
              else:
                par.kind
            # Add in the code to make the variable from the hook
            let hook = genAst(name = ident(par.name), paramKind, ctxIdent, paramName = name):
              let name = fromRequest(ctxIdent, paramName, paramKind)
            hookCalls &= hook
    hookCalls &= body
    result = newProc(
        params = @[
            returnType,
            newIdentDefs(ctxIdent, bindSym"Context")
        ],
        body = hookCalls,
        pragmas = nnkPragma.newTree(
            ident"async",
            ident"gcsafe"
        )
    )
