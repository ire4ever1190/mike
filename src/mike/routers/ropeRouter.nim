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
import ../context
import httpx
import common
# Code is modified from nest by kedean
# https://github.com/kedean/nest
    

type
    PatternType = enum
        ptrnParam
        ptrnText

    MapperKnot = object of RootObj
        isGreedy: bool
        case kind: PatternType
            of ptrnParam, ptrnText:
                value: string

    PatternNode[T] = ref object of MapperKnot
        # A leaf is at the end of tree of pattern nodes
        isLeaf: bool
        children: seq[PatternNode[T]] # Leafs do not have chilren
        # Being a terminator means that the matching can end
        isTerminator: bool
        handler: T # Only terminators have a handler
        
    Router*[T] = ref object
        verbs: array[HttpMethod, PatternNode[T]]

# Constructors
proc newRouter[T](): Router[T] =
    var verbs: array[HttpMethod, PatternNode[T]]
    result = Router[T](verbs: verbs)

proc newRopeRouter*(): Router[Handler] =
    result = newRouter[Handler]()

func empty(knots: seq[MapperKnot]): bool =
    ## Checks if a sequence of mapper knots is empty
    ## It check if its empty by seeing if there are no knots or if there is one knot and the first value is empty
    if knots.len == 0:
        result = true
    elif knots.len == 1 and knots[0].value == "":
        result = true
    

func `==`[T](node: PatternNode[T], knot: MapperKnot): bool =
    result = node.kind == knot.kind and node.value == knot.value


proc print[T](node: PatternNode[T], depth: int = 0) =
    echo " ".repeat(depth), node.value
    if node.isTerminator:
        echo " -- value: ", node.value
    if not node.isLeaf:
        for child in node.children:
            child.print(depth + 1)

proc print*[T](router: Router[T]) =
    for verb, value in router.verbs.pairs():
        if not router.verbs[verb].isNil():
            value.print()

proc generateRope(pattern: string, start: int = 0): seq[MapperKnot] {.raises: [MappingError].}=
    ## Generates a sequence of mapper knots
    var token: string
    let tokenLength = pattern.parseUntil(token, specialCharacters, start)
    var newIndex = start + tokenLength
    
    if newIndex < pattern.len(): # There is something special (parameter or path separator)
        let specialChar = pattern[newIndex]
        inc newIndex
        var scanner: MapperKnot

        case specialChar:
            of paramStart, greedyMatch:
                var paramName: string
                let paramLength = pattern.parseUntil(paramName, pathSeparator, newIndex)
                newIndex.inc(paramLength)
                if paramName == "":
                    raise newException(MappingError, "No parameter name specified: " & pattern)
                scanner = MapperKnot(isGreedy: specialChar == greedyMatch, kind: ptrnParam, value: paramName)
            
            of pathSeparator:
                scanner = MapperKnot(kind: ptrnText, value: $pathSeparator)
            else: 
                raise newException(MappingError, "Unrecognised special character: " & specialChar)

        var prefix: seq[MapperKnot]
        if tokenLength > 0:
            prefix = @[MapperKnot(kind: ptrnText, value: token)]
        prefix &= scanner
        # Check if there is more after this
        let suffix = generateRope(pattern, newIndex)
        if suffix.empty():
            result = prefix
        else:
            result = prefix.concat(suffix)
    else:
        result = newSeq[MapperKnot](tokenLength)
        for index, character in token.pairs():
            result[index] = MapperKnot(kind: ptrnText, value: $character)

proc makeTerminator[T](oldNode: PatternNode[T], knot: MapperKnot, handler: T): PatternNode[T] {.raises: [MappingError].} =
    # Makes the pattern node be a terminator with the values from the MapperKnot
    if oldNode.isTerminator:
        raise newException(MappingError, "Duplicate mapping detected")
    result = oldNode
    with result:
        kind = knot.kind
        isTerminator = true
        handler = handler


proc makeParent[T](oldNode: PatternNode[T]): PatternNode[T] = 
    ## Makes the node a parent
    ## TODO remove this
    result = oldNode
    result.isLeaf = false
                
proc indexof[T](nodes: seq[PatternNode[T]], knot: MapperKnot): int =
    ## Gets the index of a knot in a sequence of pattern nodes
    ## Returns -1 if it is not found
    for index, child in nodes.pairs():
        if child == knot:
            return index
    result = -1

proc chainTree[T](rope: seq[Mapperknot], handler: T): PatternNode[T] =
    ## Joins all the knots together to form a chain of PatternNodes
    let currentKnot = rope[0]
    let isLastKnot = rope.len() == 1
    case currentKnot.kind:
        of ptrnText: 
            result = PatternNode[T](kind: ptrnText, value: currentKnot.value, isLeaf: isLastKnot, isTerminator: isLastKnot)
        of ptrnParam:
            result = PatternNode[T](kind: ptrnParam, value: currentKnot.value, isLeaf: isLastKnot, isTerminator: isLastKnot, isGreedy: currentKnot.isGreedy)
            
    if isLastKnot:
        result.handler = handler
    else:
        result.children = @[chainTree(rope[1..^1], handler)]

proc merge[T](node: PatternNode[T], rope: seq[MapperKnot], handler: T): PatternNode[T] {.raises: [MappingError].} =
    ## Merge a pattern node and a sequence of knots together
    if rope.len() == 1:
        # Place the handler at the end of the patternNode chain
        result = node.makeTerminator(rope[0], handler)
    else:
        let 
            currentKnot = rope[0]
            nextKnot = rope[1]
            remaining = rope[1..^1]
        assert node == currentKnot

        var childIndex = -1
        result = node
        # Check if the node is a leaf
        # If the node is a leaf then it will have no chilren and so childIndex will remain -1
        if node.isLeaf:
            result.isLeaf = false
        else:
            childIndex = node.children.indexOf(nextKnot)            

        if childIndex == -1:
            # It doesn't have the child so you can just directly add the rest of the children
            result.children &= remaining.chainTree(handler) 
        else:
            # Continue the patternNode chain with the same child
            result.children[childIndex] = merge(result.children[childIndex], remaining, handler)

proc contains[T](node: PatternNode[T], rope: seq[MapperKnot]): bool =
    ## Checks for conflict between a node and a rope by seeing if they overlap
    if rope.len == 0: return
    let currentKnot = rope[0]

    if node == currentKnot:
        result = true
    else:
        # Not the same if the contain differing types
        result = node.kind != currentKnot.kind 

    if not node.isLeaf and result:
        # Check the children has well
        result = false # The children might create conflicts
        for child in node.children:
            if child.contains(rope[1..^1]): # Does the child continue the rope
                return true
    elif node.isLeaf and rope.len > 1: # The rope extends further than the node and so it does not map to the same handler
        result = false

proc map*[T](router: Router[T], verb: HttpMethod, pattern: string, handler: T) {.raises: [MappingError].}=
    ## Adds a new route to the router
    var rope = pattern
        .ensureCorrectRoute()
        .generateRope()

    var nodesToBeMerged: PatternNode[T]
    if not router.verbs[verb].isNil():
        nodesToBeMerged = router.verbs[verb]
        if nodesToBeMerged.contains(rope):
            raise newException(MappingError, "Duplicate mapping encountered: " & pattern)
    else:
        nodesToBeMerged = PatternNode[T](kind: ptrnText, value: $pathSeparator, isLeaf: true, isTerminator: false)
    router.verbs[verb] = nodesToBeMerged.merge(rope, handler)

proc extractEncodedParams(input: string, table: var StringTableRef) {.noinit.} =
    var index = 0
    while index < input.len():
        var paramValuePair: string # No clue if this will speed it up or not
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

proc compress[T](node: PatternNode[T]): PatternNode[T] =
    if node.isLeaf: # You cant compress when there is nothing left
        return node
    elif node.kind == ptrnText and not node.isTerminator and node.children.len == 1:
        # If there is only one child and it is plain text then merge the values together
        let compressedChild = compress(node.children[0])
        if compressedChild.kind == ptrnText:
            result = compressedChild
            result.value = node.value & compressedChild.value
            return
    result = node
    result.children = result.children.map(compress)

proc compress*[T](router: Router[T]) =
    ## Compresses the router to help speed up routing
    for verb, node in router.verbs.pairs():
        if not router.verbs[verb].isNil():
            router.verbs[verb] = node.compress()

proc matchTree[T](head: PatternNode[T], path: string, pathIndex: int = 0, pathParams: StringTableRef = newStringTable()): RoutingResult[T] =
    var 
        node = head
        pathIndex = pathIndex

    block matching:
        while pathIndex >= 0:
            case node.kind:
                of ptrnText:
                    if path.continuesWith(node.value, pathIndex):
                        pathIndex.inc(node.value.len())
                    else:
                        break matching
                of ptrnParam:
                    if node.isGreedy:
                        pathParams[node.value] = path[pathIndex..^1] # Get the remaining parts of the route
                        pathIndex = path.len
                    else: 
                        let newPathIndex = path.find(pathSeparator, pathIndex)
                        if newPathIndex == -1:
                            pathParams[node.value] = path[pathIndex..^1]
                            pathIndex = path.len()
                        else:
                            pathParams[node.value] = path[pathIndex..newPathIndex - 1]
                            pathIndex = newPathIndex


            if pathIndex == path.len and node.isTerminator:
                with result:
                    status = true
                    handler = node.handler
                    pathParams = pathParams
                return
            elif not node.isLeaf: # Still could some children to check
                if node.children.len == 1:
                    node = node.children[0]
                else:
                    for child in node.children:
                        result = child.matchTree(path, pathIndex, pathParams)
                        if result.status:
                            return
                    break matching 
            else:
                break matching
    result.status = false

proc route*[T](router: Router[T], verb: HttpMethod, url: string): RoutingResult[T] =
    try:
        if not router.verbs[verb].isNil():
            let (path, query) = url.getPathAndQuery()
            result = router.verbs[verb].matchTree(ensureCorrectRoute(path))
            if result.status:
                result.queryParams = newStringTable()
                query.extractEncodedParams(result.queryParams)
        else:
            result.status = false
    except MappingError:
        result.status = false

proc route*(router: Router[Handler], ctx: Context): RoutingResult[Handler] =
    result = router.route(
        ctx.request.httpMethod.get(),
        ctx.request.path.get()
    )
    if result.status:
        ctx.pathParams = result.pathParams
        ctx.queryParams = result.queryParams
        
