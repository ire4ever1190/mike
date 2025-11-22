import mike/dispatchTable
import std/[unittest, tables]

type
  Base = object of RootObj
  Child = object of Base
  Sibling = object of Base
  GrandChild = object of Child
  GrandSibling = object of Sibling
  GreatGrandSibling = object of GrandSibling

  Cousin = object of Base

import std/typeinfo {.all.}

var theThingWeAreTesting = (ref GreatGrandSibling)()
echo repr (cast[PNimType](cast[ref Base](theThingWeAreTesting)[].getTypeInfo())).typeInfoV2
echo repr (cast[PNimType](theThingWeAreTesting[].getTypeInfo())).typeInfoV2

test "Can add a value":
  var table = initDispatchTable[ref Base, int, int](proc (b: ref Base, d: int): int = d)
  check table.len == 1

suite "Calling":
  var table: DispatchTable[ref Base, string, string]
  var
    called = ""

  setup:
    template handler(x: typedesc): untyped =
      ## Returns a handler that sets the called and data fields
      proc (b: ref x, d: string): string =
        called = $x
        return d

    # Setup the table, and start adding methods
    table = initDispatchTable[ref Base, string, string](handler(Base))
    template addHandler(x: typedesc) =
      table.add(ref x, handler(x))

    # Child tree will get a method for everything
    addHandler(Child)
    addHandler(GrandChild)

    # Sibling will only have root sibling and GreatGrandSibling to check for inheritance
    addHandler(Sibling)
    addHandler(GreatGrandSibling)

  template checkCalls(a, b: typedesc) {.callsite.} =
    ## Check that when calling for type `a`, the handler for `b` is called
    var o = (ref a)()
    discard table.call(o, "")
    check called == $b

  test "Methods fall back to Base":
    checkCalls(Cousin, Base)

  test "Data is passed to method":
    var b = (ref Base)()
    check table.call(b, "Hello World") == "Hello World"

  test "Can call a child":
    checkCalls(Child, Child)

  test "Can call a GrandChild":
    checkCalls(GrandChild, GrandChild)

  test "Child calls can go up the chain":
    checkCalls(GrandSibling, Sibling)

  test "Can handle being casted":
    var b = (ref GreatGrandSibling)()
    discard table.call(cast[ref Base](b), "")

    check called == $GreatGrandSibling
