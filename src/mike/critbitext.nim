include critbits

func hasGet*[T](c: CritBitTree[T], key: string, val: var T): bool {.inline.} =
    ## Returns true if the critbit tree has `key`
    ## Also sets `val` to the result of that key
    val = c.rawGet(key)
    result = val != nil