import std/unittest
import mike/macroutils



suite "customPragmaVal":
  template hello(name: string) {.pragma.}

  {.pragma: smth, hello("something").}

  type
    Foo = object
      a {.smth.}: string
      b {.hello("test").}: int

    Bar = Foo

  let
    foo = Foo()
    bar = Bar()
  test "Can get custom val from direct object":
    check foo.b.ourGetCustomPragmaVal(hello) == "test"

  test "Can get custom val that uses a pragma alias":
    check ourGetCustomPragmaVal(foo.a, hello) == "something"

  test "Can get custom val through a type alias":
    check ourGetCustomPragmaVal(bar.b, hello) == "test"

