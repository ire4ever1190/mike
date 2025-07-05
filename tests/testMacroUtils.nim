import std/unittest
import mike/macroutils



suite "customPragmaVal":
  template hello(name: string) {.pragma.}
  template world() {.pragma.}

  {.pragma: smth, hello("something").}


  type
    Foo {.smth.} = object
      a: string
      b: int

    Bar = Foo

    SomeGeneric[T] {.hello("generic").} = T
    SomeAlias = SomeGeneric[string]
    AnotherGeneric {.hello: "foo".} = SomeAlias
    AnotherAnotherGeneric {.world.} = AnotherGeneric

  let
    foo = Foo()
    bar = Bar()
    someGeneric: SomeGeneric[string] = ""
    someAlias: SomeAlias = ""
    another: AnotherAnotherGeneric = ""

  test "Can get custom val attached to a type":
    check ourGetCustomPragmaVal(foo, hello) == "something"

  test "Can get custom val attached to a type via alias":
    check ourGetCustomPragmaVal(bar, hello) == "something"

  test "Can get custom val attached to generic":
    check ourGetCustomPragmaVal(someGeneric, hello) == "generic"

  test "Can get custom val attached to generic alias":
    check ourGetCustomPragmaVal(someAlias, hello) == "generic"

  test "All pragmas are gathered":
    check ourHasCustomPragma(another, world)
    check ourGetCustomPragmaVal(another, hello) == "foo"
