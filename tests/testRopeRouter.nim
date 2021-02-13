include mike/ropeRouter
import unittest
import tables
import random
import times
when defined(profile):
    import nimprof

template benchmark(benchmarkName: string, code: untyped) =
  block:
    let t0 = epochTime()
    code
    let elapsed = epochTime() - t0
    let elapsedStr = elapsed.formatFloat(format = ffDecimal, precision = 3)
    echo "CPU Time [", benchmarkName, "] ", elapsedStr, "s"


test "Route is corrected":
    var correctedPath = "home".ensureCorrectRoute()
    check correctedPath == "/home"
    correctedPath = "/home/".ensureCorrectRoute()
    check correctedPath == "/home"

test "Unknown characters are not allowed in route":
    expect MappingError:
        discard "/#home".ensureCorrectRoute()

template cRope(index: int, rkind: PatternType, rvalue: string): untyped =
    check:
        rope[index].kind == rkind
        rope[index].value == rvalue

test "basic rope generation":
    let rope = "/home".generateRope()
    cRope(0, ptrnText, "/")
    cRope(1, ptrnText, "h")
    cRope(2, ptrnText, "o")
    cRope(3, ptrnText, "m")
    cRope(4, ptrnText, "e")

test "Multiknot rope generation":
    let rope = "/home/user".generateRope()
    cRope(0, ptrnText, "/")
    cRope(1, ptrnText, "home")
    cRope(2, ptrnText, "/")
    cRope(3, ptrnText, "u")
    cRope(4, ptrnText, "s")
    cRope(5, ptrnText, "e")
    cRope(6, ptrnText, "r")

test "Parameter knot generation":
    let rope = "/home/:user/dashboard".generateRope()
    cRope(0, ptrnText, "/")
    cRope(1, ptrnText, "home")
    cRope(2, ptrnText, "/")
    cRope(3, ptrnParam, "user")
    cRope(4, ptrnText, "/")
    cRope(5, ptrnText, "d")
    
test "Parameter knot at the end":
    let rope = "/:user".generateRope()
    cRope(0, ptrnText, "/")
    cRope(1, ptrnParam, "user")

    
test "Route is mapped correctly":
    let router = newRouter[string]()
    router.map(HttpGet, "/home/da", "<h1>hello")
    var node = router.verbs[HttpGet]
    check:
        node.value == "/"
        node.children.len == 1
        node.children[0].value == "home"
    
    node = node.children[0]
    check:
        node.children.len == 1
        node.children[0].value == "/"

    node = node.children[0]
    check:
        node.children.len == 1
        node.children[0].value == "d"

test "Parse query parameters":
    var table: StringTableRef = newStringTable()
    "name=bob&adult=&age=27".extractEncodedParams(table)
    check:
        table["name"] == "bob"
        table["adult"] == ""
        table["age"] == "27"
    
    expect KeyError:
        check table["nokey"] == "false"

test "Compress pattern node tree":
    let pattern = "/home/user".generateRope().chainTree("foobar").compress()
    check pattern.value == "/home/user"

test "Compress pattern node tree with param":
    let pattern = "/home/:user/dashboard".generateRope().chainTree("foobar").compress()
    check:
        pattern.value == "/home/"
        pattern.children[0].value == "user"
        pattern.children[0].children[0].value == "/dashboard"
    
test "Match a basic route":
    let router = newRouter[string]()
    router.map(HttpGet, "/home/user", "foobar")
    router.compress()
    let routeResult = router.route(HttpGet, "/home/user".parseUri())
    check:
        routeResult.status
        routeResult.handler == "foobar"

test "Match a parameter route":
    let router = newRouter[string]()
    router.map(HttpGet, "/home/:user/dashboard", "foobar")
    router.compress()
    let routeResult = router.route(HttpGet, "/home/37161/dashboard".parseUri())
    check:
        routeResult.status
        routeResult.handler == "foobar"
        routeResult.pathParams["user"] == "37161"


test "Benchmark between table and trie":
    var testTable = initTable[string, string]()
    let router = newRouter[string]()
    var routes: seq[string]
    var uriRoutes: seq[URI]
    for route in "tests/testRoutes.txt".lines:
        var route = route.split(" ")[1].replace(":", "")
        try:
            router.map(HttpGet, route, "Foo Bar")
            testTable[route] = "Foo Bar"
            routes &= route
            uriRoutes &= route.parseURI()
        except MappingError:
            continue
    # router.map(HttpGet, "/home/jake", "Foo bar")
    router.compress()
    # testTable["/home/jake"] = "Foo Bar"
    # router.print()
    let url = "/home/jake".parseURI()
    let n = 500000
    benchmark "Rope":
        for i in 0..n:
            # discard router.route(HttpGet, url)
            discard router.route(HttpGet, sample(uriRoutes))

    benchmark "Hash Table":
        for i in 0..n:
            discard testTable[sample(routes)]
            # discard testTable["/home/jake"]
