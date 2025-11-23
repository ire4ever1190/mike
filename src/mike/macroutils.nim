import std/[
  macros {.all.},
  strformat,
  httpcore,
  options,
  strutils,
  setutils,
  sequtils
]
import router
import common
from context import Context


proc expectKind*(n: NimNode, k: NimNodeKind, msg: string) =
    if n.kind != k:
        error(msg, n)

type
  HandlerInfo* = object
    verbs*: set[HttpMethod]
    pos*: HandlerPos
    path*: string
    body*: NimNode
    params*: seq[tuple[name, kind: NimNode]]
      ## List of parameters. Simplified version of nnkIdentDefs that
      ## doesn't have a default type
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
    var paramStack: seq[NimNode]
    for param in info[1..^1]:
      case param.kind
      of nnkExprColonExpr: # Add type info to stack of paramters. A type has now been found
        # Add the parameter for this also
        paramStack &= param[0]

        # Add all the parameters that are using this type into the args
        for item in paramStack:
          result.params &= (item, param[1])
        paramStack.setLen(0)
      of nnkIdent, nnkPragmaExpr: # Add another parameter. They are on their own when no type is assoicated
        paramStack &= param
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

proc skip*(x: NimNode, kinds: set[NimNodeKind]): NimNode =
  # Skips past any nodes, returning the first child that isn't in the set
  var node = x
  while node.kind in kinds:
    node = node[0]
  return node

proc getPragmaNodes*(node: NimNode, nodes: var seq[NimNode]) =
  ## Gets the pragma node for a type, expect it recurses through aliases to
  ## find it.
  if node == nil:
    return
  case node.kind
  of nnkSym:
    if node.symKind == nskType:
      let impl = node.getImpl()
      if impl != nil:
        impl.getPragmaNodes(nodes)
    else:
      node.getImpl().getPragmaNodes(nodes)
  of nnkType:
    # For nnkType nodes, we need to handle them differently
    # Let's try to access the type information properly
    node[0].getPragmaNodes(nodes)
  of nnkTypeDef:
    # Check if the symbol has an pragmas
    if node[0].kind == nnkPragmaExpr:
      node[0].getPragmaNodes(nodes)
    # Now inspect the body
    node[2].getPragmaNodes(nodes)
  of nnkPragmaExpr, nnkPragma:
    nodes &= node
  of nnkBracketExpr, nnkRefTy, nnkDistinctTy:
    node[0].getPragmaNodes(nodes)
  of nnkObjectTy, nnkIdent: discard # We don't recurse into bodys
  else: discard

proc getPragmaNodes*(node: NimNode): seq[NimNode] =
  node.getPragmaNodes(result)

proc isPragma*(node, pragma: NimNode): bool =
  ## Returns true if `node` is `pragma`
  # Its just a tag and it equals the pragma
  if node.kind == nnkSym and node.eqIdent(pragma):
    return true

  # Its a call, we then need to check if the pragma getting called is what we want
  return node.kind in nnkPragmaCallKinds and node.len > 0 and node[0].isPragma(pragma)

proc getPragma*(pragmaNode, pragma: NimNode): Option[NimNode] =
  ## Gets the pragma node that corresponds to `pragma` from the actual nnkPragmaNode.
  ## Returns `None(NimNode)` if it can't be found or if it isn't a pragma
  ## This returns the first occurance of `pragma`

  # Move away from the sym that has the pragma attached
  case pragmaNode.kind
  of nnkPragmaExpr:
    return pragmaNode[1].getPragma(pragma)
  of nnkPragma:
    for p in pragmaNode:
      if p.isPragma(pragma):
        return some(p)
  else:
    return none(NimNode)

proc getPragma*(pragmas: seq[NimNode], pragma: NimNode): Option[NimNode] =
  ## Returns the first found instance of `pragma` in `pragmas`.
  for p in pragmas:
    let res = p.getPragma(pragma)
    if res.isSome():
      return res

macro ourHasCustomPragma*(n: typed, cp: typed{nkSym}): bool =
  ## Wrapper around `std/macros.hasCustomPragma` that handles aliasing.
  newLit n.getPragmaNodes().getPragma(cp).isSome()

macro ourGetCustomPragmaVal*(n: typed, cp: typed{nkSym}): untyped =
  ## Wrapper around `std/macros.hasCustomPragma` that handles aliasing.
  result = nil
  let pragmaNode = n.getPragmaNodes().getPragma(cp)
  if pragmaNode.isNone():
    error(n.repr & " doesn't have a pragma named " & cp.repr(), n) # returning an empty node results in most cases in a cryptic error,

  let p = pragmaNode.unsafeGet()
  if p.len == 2 or (p.len == 3 and p[1].kind == nnkSym and p[1].symKind == nskType): #?
    result = p[1]
  else:
    # Convert the pragma into a tuple of each param
    let def = p[0].getImpl[3]
    result = newTree(nnkPar)
    for i in 1 ..< def.len:
      let key = def[i][0]
      let val = p[i]
      result.add newTree(nnkExprColonExpr, key, val)
