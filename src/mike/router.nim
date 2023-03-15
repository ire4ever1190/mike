import std/[
    strutils,
    httpcore,
    strformat,
    parseutils,
    sequtils,
    with,
    strtabs,
    options,
    uri,
    algorithm
]

import common
import httpx


type
  MappingError* = object of ValueError

  RoutingResult*[T] = object
    pathParams*: StringTableRef
    status*: bool
    handler*: T

  PatternType* = enum
    ##[
      * *Param*: Matches a part and stores in parameter
      * *Text*: Matches a bit of text
      * *Greedy*: Matches against the end of the string
    ]##
    Text
    Param
    Greedy
  
  Handler*[T] = object
    ## Route is something that can be matched.
    ## Its position can either be pre, middle, after
    nodes*: seq[PatternNode]
    pos*: HandlerPos
    verbs: set[HttpMethod]
    handler*: T
  
  PatternNode* = object
    kind*: PatternType
    val*: string # For param this will be param name, for text this will be the text to match against
    
  Router*[T] = object
    handlers*: seq[Handler[T]]

  

const
    paramStart* = ':'
    pathSeparator* = '/'
    greedyMatch* = '^' # Matches to end and assigns to variable TODO: name greedyStart
    partMatch* = '*' # Matches one part of a url
    paramChars = {paramStart, greedyMatch, partMatch}
    specialCharacters* = {pathSeparator, paramStart, greedyMatch, partMatch}
    allowedCharacters* = {'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~'} + specialCharacters

func `==`(a, b: PatternNode): bool =
  # Text is equal if both have same value
  # Parameters are equal always since we can't tell them apart (same with greedy)
  if a.kind == b.kind:
    result = case a.kind
    of Text:
      a.val == b.val
    of Param, Greedy:
      true

func `==`*(a, b: Handler): bool =
  ## Two handlers are considered equal if they both are main handlers.
  ## This is because you can have multiple handlers run before and after the main
  ## handler but we only want one main handler
  if a.pos == b.pos and a.pos == Middle:
    # They are considered equal if have the same path and
    # some of their verbs are the same
    result = a.nodes == b.nodes and len(a.verbs * b.verbs) > 0

func cmp*[T](a, b: Handler[T]): int =
  let posCmp = cmp(a.pos, b.pos)
  if posCmp != 0:
    # Lower positions are considered smaller 
    # no matter what
    return posCmp
  else:
    let
      aFinal = a.nodes[^1].kind
      bFinal = b.nodes[^1].kind
    if aFinal != Greedy and bFinal != Greedy:
      # Haven't tested this much, but we try and match simplier (smaller amount of nodes)
      # patterns first.
      return cmp(a.nodes.len, b.nodes.len)
    elif aFinal == Greedy and bFinal == Greedy:
      # Special case is  both start with strings, we want the one that is only the root
      # to be last
      if a.nodes.len == 2 and a.nodes[0].val == "/": return 1
      if b.nodes.len == 2 and b.nodes[0].val == "/": return -1
      # Else compare everything else
      return cmp(
        a.nodes.len - 1,
        b.nodes.len - 1
      )
    else:
      # If one of them is greedy then we want the non greedy
      # one matched first
      return cmp(aFinal, bFinal)


func `$`*(nodes: seq[PatternNode]): string =
  for node in nodes:
    case node.kind
    of Text:
      result &= node.val
    of Param:
      result &= ":" & node.val
    of Greedy:
      result &= "^" & node.val



func checkPathCharacters*(path: string): (bool, char) =
    ## Returns false if there are any illegal characters
    ## also returns the illegal character
    result[0] = true
    for character in path:
      if character notin allowedCharacters:
        return (false, character)

func match*[T](handler: Handler[T], path: string): RoutingResult[T] =
  result.pathParams = newStringTable()
  var 
    i = 0
    broke = false
  for node in handler.nodes:
    var parsed = 0
    case node.kind
    of Text:
      parsed = path.skip(node.val, i)
    of Param:
      if node.val.len == 0:
        parsed = path.skipUntil('/', i) 
      else:
        var param: string
        parsed = path.parseUntil(param, '/', i)
        result.pathParams[node.val] = param.decodeUrl()
    of Greedy:
      result.pathParams[node.val] = path[i..^1].decodeUrl()
      i = path.len
      break
    if parsed == 0 and node.kind != Greedy:
      # If it didn't parse anything
      # then break out since the parsing failed
      broke = true
      break
    i += parsed
  result.status = i == path.len and not broke
  result.handler = handler.handler

func ensureCorrectPath*(path: string, checkCharacters: static[bool] = true): string {.inline.} =
    ## Checks that the route doesn't have any illegal characters and removes any trailing/leading slashes
    when checkCharacters:
      let (resonable, character) = path.checkPathCharacters()
      if not resonable:
        raise (ref MappingError)(msg: fmt"The character {character} is not allowed in the path. Please only use alphanumeric or - . _ ~ /")

    result = path
    if path.len != 1 and result[^1] == '/': # Remove last slash
      result.removeSuffix('/')

    if result[0] != '/': # Add in first slash if needed
      result.insert("/")

proc toNodes*(path: string): seq[PatternNode] =
  ## Convert a path to a series of nodes that can be matched
  let path = path.ensureCorrectPath()
  var 
    state: PatternType = Text
    i = 0

  while i < path.len:
    var val: string
    case state
    of Text:
      # Just match until end or parameter character
      i += path.parseUntil(val, paramChars, i)
    of Param, Greedy:
      case path[i]
      of greedyMatch, paramStart:
        inc i
        # Match the parameter name for greedy/parameters
        i += path.parseIdent(val, i)
        # * Greedy matches can only be at the end
        # * Parameters need a name
        if state == Greedy and i != path.len:
          raise (ref MappingError)(msg: "Greedy params must only be at the end of the path")
        if val.len == 0:
          raise (ref MappingError)(msg: "Parameter needs a name")
      of partMatch:
        # part match has no parameter name but still check it is valid
        inc i
        if i < path.len and path[i] != '/':
          raise (ref MappingError)(msg: "There must be nothing else in a * match")
      else:
        raise (ref MappingError)(msg: "Special character " & path[i] & " is not known")
    result &= PatternNode(kind: state, val: val)
    if i < path.len:
      # Check next state we are going to
      case path[i]
      of paramStart, partMatch:
        state = Param
      of greedyMatch:
        state = Greedy
      else:
        state = Text

func initHandler*[T](handler: T, path: string, pos: HandlerPos, verbs: set[HttpMethod]): Handler[T] {.raises: [MappingError].} =
  with result:
    handler = handler
    nodes = path.toNodes()
    pos = pos
    verbs = verbs
    
proc map*[T](router: var Router[T], verbs: set[HttpMethod], path: string, handler: T, pos = Middle) {.raises: [MappingError].} =
  let newHandler = initHandler(handler, path, pos, verbs)
  if newHandler in router.handlers:
    raise (ref MappingError)(msg: path & " already matches an existing path")
  router.handlers &= newHandler

proc rearrange*[T](router: var Router[T]) {.raises: [].} = 
  ## Rearranges the nodes so 
  ##  * static routes are matched before parameters
  ##  * pre handlers are at start, middile in middle, and post at the end
  ## This should be called once all routes are added so that they are in correct positions
  router.handlers.sort(cmp)


# TODO: Should be iterator but breaks with orc for some reason?
proc route*[T](router: Router[T], verb: HttpMethod, url: sink string): seq[RoutingResult[T]] {.raises: [].}=
  # Keep track of if we have found the main handler
  var foundMain = false
  for handler in router.handlers:
    if verb in handler.verbs:
      var res = handler.match(url)
      # Only pass main handlers once
      if res.status and (not foundMain or handler.pos != Middle):
        foundMain = foundMain or handler.pos == Middle
        result &= res

