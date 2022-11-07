include mike/router 
import std/[
  unittest,
  httpcore,
  sequtils
]

when defined(benchmark):
  import benchy

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

test "Two greedies are sorted correctly":
  let
    a = Handler[void](nodes: "/files/^files".toNodes(), pos: Middle)
    b = Handler[void](nodes: "/^files".toNodes(), pos: Middle)
  check:
    @[b, a].sorted(cmp) == @[a, b]
    @[a, b].sorted(cmp) == @[a, b]

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
    
  test "GET request":
    router.map(HttpGet, "/hello", "hello")
    let getRoutes = router.verbs[HttpGet]
    check getRoutes.len == 1
    let mappedRoute = getRoutes[0]
    check mappedRoute.nodes.len == 1
    check mappedRoute.handler == "hello"

  test "Before GET request":
    router.map(HttpGet, "/hello/", "hello", Pre)
    check router.verbs[HttpGet].len == 1 

  test "Error on existing route":
    # Check valid paths work
    router.map(HttpGet, "/hello", "")
    router.map(HttpGet, "/:path", "")
    # Any pre/post are allowed to be the same
    router.map(HttpGet, "/hello", "", Pre)
    router.map(HttpGet, "/hello", "", Pre)

    # Would match if everything else failed
    router.map(HttpGet, "/^something", "") 

    expect MappingError:
      router.map(HttpGet, "/hello", "")

    expect MappingError:
      router.map(HttpGet, "/:somethingelse", "")

    router.map(HttpGet, "/file/^file", "")
    expect MappingError:
      router.map(HttpGet, "/file/^idk", "")
    
      
suite "Single routing":
  var router = Router[string]()
  # Setup all the routes to be used for testing
  # Simple routes
  router.map(HttpGet, "/index", "Index")
  router.map(HttpGet, "/pages", "Pages")
  router.map(HttpGet, "^everything", "Everything")
  router.map(HttpGet, "/:anything/home", "Something but home")
  router.map(HttpGet, "/pages/:page", "Any page")
  router.map(HttpGet, "/pages/home", "Home")
  router.map(HttpGet, "/pages/something", "Some")
  router.map(HttpGet, "/static/^file", "File")

  router.rearrange()
  echo router
  template checkRoute(path, expected: string): RoutingResult =
    block:
      let res = toSeq: router.route(HttpGet, path)
      check res.len == 1
      check res[0].handler == expected
      res[0]
      
  test "Index and pages":
    discard checkRoute("/index", "Index")
    discard checkRoute("/pages", "Pages")
    
  test "Home and something":
    discard checkRoute("/pages/home", "Home")
    discard checkRoute("/pages/something", "Some")

  test "Param matching":
    discard checkRoute("/pages/different", "Any page")
    discard checkRoute("/l/home", "Something but home")

  test "Catch all":
    discard checkRoute("/404", "Everything")
    discard checkRoute("/", "Everything")

  test "Empty greedy is matched":
    # discard checkRoute("/static/test", "File")
    discard checkRoute("/static/", "File")


  when defined(benchmark):
    timeIt "Routing":
      for h in router.route(HttpGet, "/404/case"):
        for i in 0..<1_000_000:
          keep h.status
    
suite "Multimatch":
  var router = Router[string]()

  router.map(HttpGet, "/index", "Index")
  router.map(HttpGet, "/page/deep", "2nd page")
  router.map(HttpGet, "/^path", "Logger", Post)
  router.map(HttpGet, "/*", "Root page", Pre)

  # TODO: Test global matchers
  
  router.rearrange()
  
  template checkRoute(path: string, expected: seq[string]) =
    block:
      let res = toSeq: router.route(HttpGet, path)
      check res.len == expected.len
      check res.mapIt(it.handler) == expected
      
  test "Match post and main handler":
    checkRoute("/page/deep", @["2nd page", "Logger"])

  test "Match pre, post, and main handler":
    checkRoute("/index", @["Root page", "Index", "Logger"])
