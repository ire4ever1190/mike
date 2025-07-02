import std/unittest
import mike/macroutils



suite "customPragmaVal":
  template hello(name: string) {.pragma.}
  template world() {.pragma.}

  {.pragma: smth, hello("something").}


  type
    Foo {.hello("test").} = object
      a {.smth.}: string
      b {.hello("test").}: int

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

  test "Can get custom val from direct object":
    check foo.b.ourGetCustomPragmaVal(hello) == "test"

  test "Can get custom val that uses a pragma alias":
    check ourGetCustomPragmaVal(foo.a, hello) == "something"

  test "Can get custom val through a type alias":
    check ourGetCustomPragmaVal(bar.b, hello) == "test"

  test "Can get custom val attached to a type":
    check ourGetCustomPragmaVal(foo, hello) == "test"

  test "Can get custom val attached to a type via alias":
    check ourGetCustomPragmaVal(bar, hello) == "test"

  test "Can get custom val attached to generic":
    check ourGetCustomPragmaVal(someGeneric, hello) == "generic"

  test "Can get custom val attached to generic alias":
    check ourGetCustomPragmaVal(someAlias, hello) == "generic"

  test "All pragmas are gathered":
    check ourHasCustomPragma(another, world)
    check ourGetCustomPragmaVal(another, hello) == "foo"
