import std/[
  macros,
  strformat,
  httpcore,
  options,
  strutils,
  tables,
  setutils,
  sequtils
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
    mutable*: bool
      ## True if the parameter is `var T`
    bodyType*: NimNode
    pragmas*: Table[string, NimNode]

  HandlerInfo* = object
    verbs*: set[HttpMethod]
    pos*: HandlerPos
    path*: string
    body*: NimNode
    params*:  seq[ProcParameter]
    pathParams*: seq[string]

func findVerb(x: string): Option[HttpMethod] =
  ## Finds verb that matches string. Is fully case insensitive
  let ident = toLowerAscii(x)
  for verb in HttpMethod:
    if ident.eqIdent(toLowerAscii($verb)):
      return some verb

proc getVerb(info: NimNode): Option[(set[HttpMethod], HandlerPos)] =
  ## Parses correct verb from an ident
  case info.kind
  of nnkBracket, nnkBracketExpr:
    var
      positionNode:NimNode
      verbNodes: seq[NimNode]
    # Extract the needed nodes
    if info.kind == nnkBracket:
      verbNodes = toSeq(info)
    else:
      verbNodes = info[1..^1]
      positionNode = info[0]

    # Find all the verbs stored
    var verbs: set[HttpMethod]
    for ident in verbNodes:
      let verb = findVerb($ident)
      if verb.isSome():
        verbs.incl verb.unsafeGet()
      else:
        (fmt"Unknown verb {ident}").error(info)
    # Find the position if applicable
    var position = Middle
    if positionNode != nil:
      for pos in [Pre, Post]:
        if positionNode.eqIdent($pos):
          position = pos
    return some (verbs, position)

  of nnkIdent:
    for position in HandlerPos:
      if info.eqIdent($position & "any"):
        return some (fullSet(HttpMethod), position)
      for verb in HttpMethod:
        if info.eqIdent($position & toLowerAscii($verb)):
          return some ({verb}, position)
  else:
    echo info.treeRepr
    "This shouldn't have happened, report this stacktrace on github".error(info)

proc getHandlerInfo*(path: string, info, body: NimNode): HandlerInfo =
  ## Gets info about a handler.
  result.path = path
  # Run assert, though it shouldn't be triggered ever since we check this before
  if info.kind notin {nnkIdent, nnkObjConstr, nnkCall, nnkBracket, nnkBracketExpr}:
    "You have specified a route incorrectly. It should be like `get(<parameters>):` or `get:`".error(info)
  var verbIdent: NimNode
  case info.kind
  of nnkIdent, nnkBracket, nnkBracketExpr:
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
        let varType = param[1].kind == nnkVarTy
        let kind = if varType: param[1][0] else: param[1]
        for item in paramStack.mitems:
          item.kind = kind
          item.mutable = varType
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
        "Expects `name: type` for parameter".error(param)


  # Get the verb from the ident
  let verbInfo = verbIdent.getVerb()
  if verbInfo.isSome:
    let (verb, pos) = verbInfo.get()
    result.verbs = verb
    result.pos = pos
  else:
    ("Not a valid route verb `" & $toStrLit(verbIdent) & "`").error(verbIdent)


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

    # Then add all the calls which require the context
    for par in parameters:
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
      let hookCall = genAst(paramKind, ctxIdent, paramName = name):
        when fromRequest(ctxIdent, paramName, paramKind) is Future:
          await fromRequest(ctxIdent, paramName, paramKind)
        else:
          fromRequest(ctxIdent, paramName, paramKind)
      let hookDeclare = genAst(name = ident(par.name), hookCall, mutable = par.mutable):
        when mutable:
          var name = hookCall
        else:
          let name = hookCall
      hookCalls &= hookDeclare
    hookCalls &= nnkBlockStmt.newTree(newEmptyNode(), body)
    let
      name = genSym(nskProc, path)
      asyncPragma = ident"async"
    asyncPragma.copyLineInfo(handler)
    result = newStmtList(
      newProc(
        name = name,
        params = @[
            returnType,
            newIdentDefs(ctxIdent, bindSym"Context")
        ],
        body = hookCalls,
        pragmas = nnkPragma.newTree(
            asyncPragma,
            ident"gcsafe"
        )
      ),
      name
    )
