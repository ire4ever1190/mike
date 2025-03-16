import std/tables
import std/options
import std/typeinfo {.all.}

type
  Handler[O, D] = proc (obj: O, data: D)
  DispatchTable*[O: ref object; D] = Table[int, Handler[O, D]]
    ## Dynamic dispatch table. Handlers get passed the object that is getting called
    ## along with a bit of data.
    ##
    ## Implemented so we can get late binding for method calling

proc getKey*[T](obj: T): int =
  ## Generates a key for the lookup table.
  ## Currently uses RTTI to get the address of the objects type info
  return cast[int](obj.getTypeInfo())

template checkInheritance(c: typedesc, p: typedesc) {.callsite.} =
  ## Performs a compile time check that `c` inherits `p`
  when c isnot p:
    {.error: $c & " does not inherit from " & $p.}

proc add*[O, T, D](table: var DispatchTable[O, D], typ: typedesc[T], handler: Handler[T, D]) =
  ## Adds a new method into the lookup table
  checkInheritance(T, O)
  table[default(typ).getKey()] = cast[ptr Handler[O, D]](addr handler)[]

proc initDispatchTable*[O, D](base: Handler[O, D]): DispatchTable[O, D] =
  ## Creates a new lookup table. Must have a base handler which corresponds to the root object
  result = default(DispatchTable[O, D])
  result.add(O, base)

proc call*[O, T, D](table: DispatchTable[O, D], val: T, data: D) =
  ## Calls the appropriate handler for an object in the lookup table
  checkInheritance(T, O)
  # Search until we find a method that matches the object.
  # Will eventually find the base handler
  var info = cast[PNimType](val.getTypeInfo())
  while info != nil:
    let key = cast[int](info)
    echo key
    if key in table:
      table[key](val, data)
      break
    info = info[].base
