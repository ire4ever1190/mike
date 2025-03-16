import mike/dispatchTable
import std/[unittest, tables]

type
  Base = object of RootObj
  Child = object of RootObj
  Sibling = object of RootObj
  GrandChild = object of Child
  GrandSibling = object of Sibling
  GreatGrandSibling = object of GrandSibling

  Cousin = object of Base

echo Cousin() of Base

test "Can add a value":
  var table = initDispatchTable[Base, int](proc (b: Base, d: int) = discard)
  check table.len == 1

suite "Calling":
  var table: DispatchTable[Base, string]
  var
    called = ""
    data = ""

  setup:
    template handler(x: typedesc): untyped =
      ## Returns a handler that sets the called and data fields
      proc (b: x, d: string) =
        called = $x
        data = d

    # Setup the table, and start adding methods
    table = initDispatchTable[Base, string](handler(Base))
    template addHandler(x: typedesc) =
      table.add(x, handler(x))

    # Child tree will get a method for everything
    addHandler(Child)
    addHandler(GrandChild)

    # Sibling will only have root sibling and GreatGrandSibling to check for inheritance
    addHandler(Sibling)
    addHandler(GreatGrandSibling)

  test "Methods fall back to Base":
    var c = Cousin()
    table.call(c, "")
    check called == "Base"

  test "Data is passed to method":
    var b = Base()
    table.call(b, "Hello World")
    check data == "Hello World"

  test "Can call a child":
    var c = Child()
    table.call(c, "")
    check called == "Child"

  test "Can call a GrandChild":
    var c = GrandChild()
    table.call(c, "")
    check called == "GrandChild"

  test "Child calls can go up the chain":
    var c = GrandSibling()
    table.call(c, "")
    check called == "Sibling"



