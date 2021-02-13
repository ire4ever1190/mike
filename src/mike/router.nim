import tables
import std/critbits
import parseutils

const 
    arraySize = 93
    arrayOffset = 32

type
    TrieNode[T] = ref object
        chr*: char
        data*: T
        isEnd*: bool
        parameterKey: string
        children*: array[arraySize, TrieNode[T]]

    Route = object
        parameters: seq[(string, int)]

proc newTrie*[T](chr: char = '\x00'): TrieNode[T] =
    var children: array[arraySize, TrieNode[T]]
    result = TrieNode[T]()
    result.chr = chr
    result.children = children

proc `$`*[T](trie: TrieNode[T]): string =
    result = "char: " & trie.chr & " data: " & trie.data & "\n"
    for child in trie.children:
        if not child.isNil():
            result &= child.chr & " "

proc `[]=`*[T](trie: var TrieNode[T], key: string, val: T) =
    var currentNode = trie
    var index = 0
    while index < len(key):
        var chr = key[index]
        if chr == ':':
            let child = currentNode.children[ord('*') - arrayOffset]
            # Parse the parameter name
            var parameterKey = ""
            inc index # Skip ':'
            while index < len(key) and key[index] != '/':
                parameterKey &= key[index]
                inc index
            # If it has a child already then use the child
            if not child.isNil():
                currentNode = child
            else:
                # Else create a new node
                var newNode = newTrie[T](chr = '*')
                newNode.parameterKey = parameterKey
                currentNode.children[ord('*') - arrayOffset] = newNode
                currentNode = newNode
            
        else:
            var child = currentNode.children[ord(chr) - arrayOffset]
            if not child.isNil():
                currentNode = child
            else:
                var newNode = newTrie[T](chr = chr)
                currentNode.children[ord(chr) - arrayOffset] = newNode
                currentNode = newNode
        inc index
    currentNode.isEnd = true
    currentNode.data = val


     

proc `[]`*[T](trie: TrieNode[T], key: string): T =
    var currentNode = trie
    var index = 0
    while index < len(key):
        var chr = key[index]
        var child = currentNode.children[ord(chr) - arrayOffset]
        if not child.isNil():
            currentNode = child
        else:
            # Check if there is * in the children
            # If so, skip characters until it gets to the next slash
            if not currentNode.children[ord('*') - arrayOffset].isNil():
                var parameterValue = ""
                index += key.parseUntil(parameterValue, '/', start = index)
                # index += key.skipUntil('/', start = index)
                currentNode = currentNode.children[ord('*') - arrayOffset]
                # result.urlParameters[currentNode.parameterKey] = parameterValue
            else:
                raise newException(KeyError, key & " not found in the trie tree")
        inc index 
    if currentNode.isEnd:
        # result.data = currentNode.data
        result = currentNode.data
    else:
        raise newException(KeyError, key & " does not have an end value")

export critbits
