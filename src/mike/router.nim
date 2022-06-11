import std/[
    strutils,
    httpcore,
    strformat,
    parseutils,
    sequtils,
    with,
    strtabs,
    options,
    uri
]
import context
import common
import httpx
# Code is modified from nest by kedean
# https://github.com/kedean/nest

type
  MappingError* = object of ValueError

  RoutingResult*[T] = object
    pathParams*: StringTableRef
    queryParams*: StringTableRef
    status*: bool
    handler*: T
    befores, afters: seq[T]

  PatternType = enum
    ##[
      * *Param*: Matches a part and stores in parameter
      * *Text*: Matches a bit of text
      * *Greedy*: Matches against the end of the string
    ]##
    Param
    Text
    Greedy
  
  Handler[T] = object
    ## Route is something that can be matched.
    ## Its position can either be pre, middle, after
    nodes: seq[PatternNode]
    pos: HandlerPos
    handler: T
  
  PatternNode = object
    kind: PatternType
    val: string # For param this will be param name, for text this will be the text to match against
    
  Router*[T] = ref object
    verbs: array[HttpMethod, seq[Handler[T]]]

  

const
    paramStart* = ':'
    pathSeparator* = '/'
    greedyMatch* = '^' # Matches to end and assigns to variable TODO: name greedyStart
    partMatch* = '*' # Matches one part of a url
    paramChars = {paramStart, greedyMatch, partMatch}
    specialCharacters* = {pathSeparator, paramStart, greedyMatch, partMatch}
    allowedCharacters* = {'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~'} + specialCharacters

func `==`(a, b: PatternNode): bool =
  ## Pattern nodes are only considered equal if they are
  ##  - The same kind
  ##  - Both text
  ##  - text values match
  ## Parameters are never considered equal since we allow to store multiple of them
  if a.kind == b.kind:
    result = case a.kind
    of Text:
      a.val == b.val
    else:
      false

func `==`(a, b: Handler): bool =
  ## Two handlers are considered equal if they both are main handlers.
  ## This is because you can have multiple handlers run before and after the main
  ## handler but we only want one main handler
  if a.pos == b.pos and a.pos == Middle:
    a.nodes == b.nodes


func getPathAndQuery*(url: string): tuple[path, query: string] {.inline.} =
    ## Returns the path and query string from a url
    let pathLength = url.parseUntil(result.path, '?')
    if pathLength != url.len():
        result.query = url[pathLength + 1 .. ^1]

func checkPathCharacters*(path: string): (bool, char) =
    ## Returns false if there are any illegal characters
    ## also returns the illegal character
    result[0] = true
    for character in path:
        if character notin allowedCharacters:
            return (false, character)

func match*[T](handler: Handler[T], path: string): RoutingResult[T] =
  result.pathParams = newStringTable()
  var i = 0
  for node in handler.nodes:
    case node.kind
    of Text:
      i += path.skip(node.val, i)
    of Param:
      if node.val.len == 0:
        i += path.skipUntil('/', i) 
      else:
        var param: string
        i += path.parseUntil(param, '/', i)
        result.pathParams[node.val] = param
    of Greedy:
      result.pathParams[node.val] = path[i..^1]
      i = path.len
  result.status = i == path.len
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

func initHandler*[T](handler: T, path: string, pos: HandlerPos): Handler[T] =
  with result:
    handler = handler
    nodes = path.toNodes()
    pos = pos
    
proc map*[T](router: Router[T], verb: HttpMethod, pattern: string, handler: T, pos = Middle) {.raises: [MappingError].} =
  discard

iterator route*[T](items: openArray[Handler[T]], path: string): lent Handler[T] =
  # Keep track of if we have found the main handler
  var foundHandler = false

proc extractEncodedParams(input: string, table: var StringTableRef) =
    var index = 0
    while index < input.len():
        var paramValuePair: string 
        let 
            pairSize = input.parseUntil(paramValuePair, '&', index)
            equalIndex = paramValuePair.find('=')
        index.inc(pairSize + 1)

        if equalIndex == -1:
            table[paramValuePair] = ""
        else:
            let 
                key = paramValuePair[0 .. equalIndex - 1]
                value = paramValuePair[equalIndex + 1 .. ^1]
            table[key] = value

proc route*[T](router: Router[T], verb: HttpMethod, url: string): RoutingResult[T] =
  discard
  
proc route*(router: Router[Handler], ctx: Context): RoutingResult[Handler] =
    result = router.route(
        ctx.request.httpMethod.get(),
        ctx.request.path.get()
    )
        
