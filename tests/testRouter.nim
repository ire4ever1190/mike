include mike/router 
import std/[
  unittest,
  httpcore,
  sequtils
]

suite "Invalid routes":
  test "No parameter name passed for param":
    expect MappingError:
      discard "/page/:".toNodes()
    expect MappingError:
      discard "/page/:".toNodes()

  test "Greedy param isn't at the end":
    expect MappingError:
      discard "/^rest/something".toNodes()

  test "Glob match has name":
    expect MappingError:
      discard "/*something".toNodes()

suite "Valid routes":
  test "Full text":
    let nodes = "/home/test/".toNodes()
    check nodes.len == 1
    check nodes[0].val == "/home/test"
    
  test "Text and param":
    let nodes = "/home/:page".toNodes()
    check nodes.len == 2
    check:
      nodes[0].val == "/home/"
      nodes[1].kind == Param
      nodes[1].val == "page"

  test "Param at the start":
    let nodes = ":page".toNodes()
    check nodes.len == 2
    check:
      nodes[0].val == "/"
      nodes[1].val == "page"

  test "Any match":
    let nodes = "/file/*/delete".toNodes()
    check nodes.len == 3
    check:
      nodes[1].kind == Param
      nodes[1].val == ""

  test "Greedy":
    let nodes = "/file/^path".toNodes
    check nodes.len == 2
    check:
      nodes[1].kind == Greedy
      nodes[1].val == "path"

suite "Matching":
  template checkMatches(pattern, path: string) =
    let handler = initHandler("foo", path, Middle)
    check handler.match(path).status
  test "Full text":
    checkMatches("/home/test", "/home/test")

  test "Parameter":
    let handler = initHandler("test", "/page/:page", Middle)
    let res = handler.match("/page/index")
    check res.status
    check:
      res.handler == "test"
      res.pathParams["page"] == "index"

  test "Part":
    let pattern = "/page/*/something"
    checkMatches(pattern, "/page/l/something")
    checkMatches(pattern, "/page/hh/something")

  test "Greedy":
    let handler = initHandler("greed", "/file/^path", Middle)
    block:
      let res = handler.match("/file/index.html")
      check:
        res.status
        res.pathParams["path"] == "index.html"
    block:
      let res = handler.match("/file/images/logo.png")
      check:
        res.status
        res.pathParams["path"] == "images/logo.png"

suite "Mapping":
  setup:
    var router = Router[string]()
    
  test "Map GET request":
    let getRoutes = router.verbs[HttpGet]
    check getRoutes.len == 1
    let mappedRoute = getRoutes[0]
    check mappedRoute.nodes.len == 1
    check mappedRoute.handler == "/hello/"

suite "Routing":
  var router = Router[string]()
  # Setup all the routes to be used for testing
  # Simple routes
  router.map(HttpGet, "/index", "Index")
  router.map(HttpGet, "/pages", "Pages")
  router.map(HttpGet, "/pages/home", "Home")
  router.map(HttpGet, "/pages/something", "Home")
  router.map(HttpGet, "/pages/:page", "Any page")


  # test "Route single handler"
