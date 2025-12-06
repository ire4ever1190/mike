## Internal module that implements late binding dispatch table.
## This is used for the error handling implementation so that handling a parent
## exception automatically handles the child exceptions (if nothing else handles them)

import std/tables
import std/options
import system {.all.}
import std/importutils

const newTypeInfo = defined(nimv2)

type
  DispatchKey = (when newTypeInfo: uint32 else: BiggestUint)
    ## Represents a key in the dispatch table

  DispatchMethod*[O, D, R] = proc (obj: O, data: D): R
    ## Method in the dispatch table. Takes in the object along with an argument

  DispatchTable*[O: ref object; D; R] = Table[DispatchKey, DispatchMethod[O, D, R]]
    ## Dynamic dispatch table. DispatchMethods get passed the object that is getting called
    ## along with a bit of data.
    ##
    ## Implemented so we can get late binding for method calling

proc getTypeInfo(obj: ref object): (when newTypeInfo: PNimTypeV2 else: PNimType) =
  ## Gets RTTI for an object
  # The RootObj has a `m_type` field containing the RTTI info
  {.emit: [result, " = (", (ref RootObj)(obj), ")->m_type;"].}

iterator getKeys(obj: ref object): DispatchKey =
  ## Returns opache keys that represent the inheritance tree.
  ## Starts at the current type and works itself way down to the base type
  let info = getTypeInfo(obj)
  privateAccess(type(info))

  when newTypeInfo:
    # We have a list of display tokens that we can work down with
    for i in countdown(info.depth, 0):
      yield info.display[i]
  else:
    # We need to climb up the nim type info tree
    var curr = info
    while curr != nil:
      yield cast[DispatchKey](curr)
      curr = curr.base

proc getKey[T: ref object](obj: T): DispatchKey =
  ## Generates a key for the lookup table.
  ## Currently uses RTTI to get the address of the objects type info.
  # The RootObj has a `m_type` field containing the RTTI info.
  # The typeInfo function doesn't correctly handle casting, so we need to manually access the field
  for key in obj.getKeys():
    return key

template checkInheritance(c: typedesc, p: typedesc) {.callsite.} =
  ## Performs a compile time check that `c` inherits `p`
  when c isnot p:
    {.error: $c & " does not inherit from " & $p.}

proc add*[O, T, D, R](table: var DispatchTable[O, D, R], typ: typedesc[T], handler: DispatchMethod[T, D, R]) =
  ## Adds a new method into the lookup table
  checkInheritance(T, O)
  table[typ().getKey()] = cast[ptr DispatchMethod[O, D, R]](addr handler)[]

proc initDispatchTable*[O, D, R](base: DispatchMethod[O, D, R]): DispatchTable[O, D, R] =
  ## Creates a new lookup table. Must have a base handler which corresponds to the root object
  result = default(DispatchTable[O, D, R])
  result.add(O, base)

proc call*[O, T, R, D](table: DispatchTable[O, D, R], val: T, data: D): R =
  ## Calls the appropriate handler for an object in the lookup table
  checkInheritance(T, O)
  for key in getKeys(val):
    if key in table:
      return table[key](val, data)

export tables
