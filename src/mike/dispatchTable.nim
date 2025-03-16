import std/tables
import std/options
import std/typeinfo {.all.}

type
  DispatchMethod*[O, D, R] = proc (obj: O, data: D): R
    ## Method in the dispatch table. Takes in the object along with an argument

  DispatchTable*[O: ref object; D; R] = Table[int, DispatchMethod[O, D, R]]
    ## Dynamic dispatch table. DispatchMethods get passed the object that is getting called
    ## along with a bit of data.
    ##
    ## Implemented so we can get late binding for method calling

proc getKey[T: ref object](obj: T): int =
  ## Generates a key for the lookup table.
  ## Currently uses RTTI to get the address of the objects type info
  return cast[int](obj[].getTypeInfo())

template checkInheritance(c: typedesc, p: typedesc) {.callsite.} =
  ## Performs a compile time check that `c` inherits `p`
  when c isnot p:
    {.error: $c & " does not inherit from " & $p.}

proc add*[O, T, D, R](table: var DispatchTable[O, D, R], typ: typedesc[T], handler: DispatchMethod[T, D, R]) =
  ## Adds a new method into the lookup table
  checkInheritance(T, O)
  table[default(typ).getKey()] = cast[ptr DispatchMethod[O, D, R]](addr handler)[]

proc initDispatchTable*[O, D, R](base: DispatchMethod[O, D, R]): DispatchTable[O, D, R] =
  ## Creates a new lookup table. Must have a base handler which corresponds to the root object
  result = default(DispatchTable[O, D, R])
  result.add(O, base)

proc call*[O, T, R, D](table: DispatchTable[O, D, R], val: T, data: D): R =
  ## Calls the appropriate handler for an object in the lookup table
  checkInheritance(T, O)

  # Search until we find a method that matches the object.
  # Will eventually find the base handler
  var info = cast[PNimType](val[].getTypeInfo())
  while info != nil:
    let key = cast[int](info)
    if key in table:
      return table[key](val, data)

    info = info[].base
