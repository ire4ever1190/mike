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
