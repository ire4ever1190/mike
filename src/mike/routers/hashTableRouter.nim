import critbitext
import std/[
    httpcore,
    strtabs,
    strutils,
    tables
]

type
    HashTableRouter[T] = Table[string, string]

func newRouter[T](): CritBitRouter[T] =
    var verbs: array[HttpMethod, CritBitTree[T]]
    result = Router[T](verbs: verbs)

func newCritBitRouter(): CritBitRouter[Handler] =
    result = newRouter[Handler]()

proc map[T](node: PatternNode[T], rope: seq[MapperKnot], handler: T) =
    var currentNode = node
    for knot in rope:
        if knot.kind in {ptrnParam, ptrnText}:
            if currentNode.children.hasKey(knot.value):
                currentNode = currentNode.children[knot.value]
            else:
                var newNode = newPatternNode[T](knot.kind)
                currentNode.children[knot.value] = newNode
                currentNode = newNode
    currentNode.isTerminator = true
    currentNode.handler = handler
