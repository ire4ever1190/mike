import mike
import utils
import std/[
  json,
  exitprocs,
  strutils,
  strformat,
  os,
  threadpool,
  unittest,
  httpclient,
  setutils,
  options
]



type
  Person* = ref object of RootObj
    name*: string

  Frog = object
    colour: string

#
# Routing
#

servePublic("tests/public", "static", {
  "": "index.html"
})

"/" -> get:
    return "index"

"/hello/world" -> get:
    result = "foo bar"

"/user/:name" -> get:
    return "Hello " & ctx.pathParams["name"]

"/file/^file" -> get:
    return "Serving file: " & ctx.pathParams["file"]

"/returnformat" -> get:
    let tag = if ctx.queryParams["format"] == "big":
                "h1"
            else:
                "p"
    return fmt"""<{tag}>{ctx.queryParams["text"]}</{tag}>"""


"/uppercase" -> post:
    return ctx.request.body.get().toUpperAscii()

"/person/:name" -> beforeGet():
    ctx &= Person(name: ctx.pathParams["name"])

"/person/:name" -> get():
    return "Hello, " & ctx[Person].name

"/another" -> beforeGet():
  ctx &= Person(name: "human")
  ctx.response.body = "another "

"/another" -> get:
    ctx.response.body &= "one"

"/another" -> afterGet():
  assert ctx[Person].name == "human"

"/upper/:name" ->  beforeGet():
    ctx &= Person()
    var person = ctx[Person]
    person.name = ctx.pathParams["name"].toUpperAscii()

"/upper/:name" -> get():
    return "Good evening, " & ctx[Person].name

"/helper/json" -> get:
    ctx.json = Frog(colour: "green")

"/helper/sendjson" -> get:
    ctx.send Frog(colour: "green")

"/form" -> get:
    let form = ctx.urlForm()
    ctx.send(form["hello"])

"/redirect" -> get:
    ctx.redirect "/"

"/form" -> post:
    let form = ctx.urlForm()
    ctx.send(form["hello"] & " " & form["john"])

"/multipart" -> post:
  let form = ctx.multipartForm()
  assert form["test"].filename.get() == "testServer.nim"
  assert form["test"].value == readFile("tests/testServer.nim")
  assert form["msg"].value == "hello"
  ctx.send("done")

"/customdata/1" -> get:
  if ctx[Option[Person]].isNone:
    ctx.send "Not found"

"/file" -> [get, head]:
  ctx.setHeader("Cache-Control", "public, max-age=432000")
  await ctx.sendFile(ctx.queryParams["file"], allowRanges = true)

"/keyerror" -> get:
  raise (ref KeyError)(msg: "Should be overridden")

"/genericerror" -> get:
  raise (ref Exception)(msg: "Something failed")

"/shoulderror" -> beforeGet:
  raise (ref Exception)(msg: "Something failed")

"shoulderror" -> get:
  ctx.send("This shouldn't send")

"/multi/1" -> [get, post]:
  discard

"/multi/2" -> any:
  discard

"/multi/3" -> beforeAny:
  ctx &= Person(name: $ctx.httpMethod())

"/multi/3" -> before[get, post]:
  ctx.status = Http429

"/multi/3" -> get:
  ctx.send ctx[Person].name

"/multi/4" -> before[get, post](x: Query[string]):
  ctx.send x

"/stream/chunked" -> get:
  ctx.startChunking()
  for word in ["Hello world foo bar"]:
    ctx.sendChunk(word & " ")
  ctx.sendChunk("")

"/stream/sse" -> get:
  ctx.startSSE()
  ctx.sendEvent("", "hello")
  ctx.sendEvent("ping", "pong")
  ctx.sendEvent("long", "hello\nworld")
  ctx.stopSSE()

"/cookie" -> get:
  ctx &= initCookie("foo", "bar")

"/data/something/other" -> beforeGet:
  discard

"/anyerror" -> get:
  raise (ref ValueError)(msg: "This was thrown")

KeyError -> thrown:
  ctx.send("That key doesn't exist")

CatchableError -> thrown:
  ctx.send("Some error was thrown")

runServerInBackground()
# run()

#
# Tests
#

suite "GET":
  test "Basic":
    check get("/").body == "index"

  test "404":
    let resp = get("/notfound")
    check resp.body.parseJson() == %* {
      "kind": "NotFoundError",
      "detail": "/notfound could not be found",
      "status": 404
    }
    check resp.code == Http404

  test "Path parameter":
    check get("/user/jake").body == "Hello jake"

  test "Query Parameter":
    check get("/returnformat?format=big&text=hello").body == "<h1>hello</h1>"

  test "Greedy match":
    check get("/file/public/index.html").body == "Serving file: public/index.html"

  test "Stress test": # Test for a nil access error
    stress:
      check get("/").body == "index"

suite "POST":
    test "Basic":
        check post("/uppercase", "hello").body == "HELLO"

suite "Misc":
  test "HEAD doesn't return body":
    let resp = client.request(root / "/notfound", httpMethod = HttpHead)
    check resp.body == ""
    check resp.code == Http404

  test "OPTIONS doesn't return body":
    let resp = client.request(root / "/notfound", httpMethod = HttpHead)
    check resp.body == ""
    check resp.code == Http404

  test "Cookies are sent in response":
    let resp = get("/cookie")
    check resp.headers.hasKey("Set-Cookie")
    check resp.headers["Set-Cookie"] == "foo=bar; Secure; SameSite=Lax"

suite "Custom Data":
  test "Basic":
    check get("/person/john").body == "Hello, john"

  test "In middleware":
    check get("/upper/jake").body == "Good evening, JAKE"

  test "Allow non existing":
    check get("/customdata/1").body == "Not found"

  test "Stress test":
    stress:
        check get("/upper/hello").body == "Good evening, HELLO"

  test "Custom ctx before and after but not with main handler":
    stress:
       check get("/another").body == "another one"


suite "Helpers":
  test "Json response":
    check get("/helper/json").body == "{\"colour\":\"green\"}"
    check get("/helper/sendjson").body == "{\"colour\":\"green\"}"

  test "Redirect":
    check get("/redirect").body == "index"

  test "Send file":
    let resp = get("/file?file=mike.nimble")
    check resp.body == "mike.nimble".readFile()
    check resp.headers["Content-Type"] == "text/nimble"
    check resp.headers["Cache-Control"] == "public, max-age=432000"

  test "Send file with HEAD request":
    let resp = head("/file?file=mike.nimble")
    check resp.code == Http200
    check resp.body == ""
    check resp.headers["Content-Type"] == "text/nimble"
    check resp.headers["Cache-Control"] == "public, max-age=432000"

  test "Range request header set":
    check head("/file?file=mike.nimble").headers["Accept-Ranges"] == "bytes"


suite "Forms":
  test "URL encoded form GET":
    check get("/form?hello=world&john=doe").body == "world"

  test "URL encoded form POST":
    check post("/form", "hello=world&john=doe").body == "world doe"

  test "Multipart form":
    let client = newHttpClient()
    var data = newMultipartData()
    data.addFiles({"test": "tests/testServer.nim"})
    data["msg"] = "hello"
    check client.postContent("http://127.0.0.1:8080/multipart", multipart = data) == "done"

suite "Error handlers":
  test "Handler can be overridden":
    check get("/keyerror").body == "That key doesn't exist"

  test "Default handler catches exceptions":
    let resp = get("/genericerror")
    check resp.body.parseJson() == %* {
      "kind": "Exception",
      "detail": "Something failed",
      "status": 400
    }
    check resp.code == Http400

  test "Routes stop getting processed after an error":
    let resp  = get("/shoulderror")
    check resp.code == Http400

  test "Parent can catch subclassed errors":
    let resp = get("/anyerror")
    check resp.body == "Some error was thrown"

suite "Public files":
  const indexFile = readFile("tests/public/index.html")
  test "Get static file":
    check get("/static/index.html").body == indexFile

  test "404 when accessing file that doesn't exist":
    check get("/static/nothere.js").code == Http404

  test "403 when trying to escape the folder":
    check get("/static/../config.nims").code == Http403

  test "Renames work":
    check get("/static/").body == indexFile

  test "Content-Type is set":
    check get("/static/").headers["Content-Type"] == "text/html"

  test "Works with HEAD":
    check head("/static/").headers == get("/static/").headers


suite "Multi handlers":
  const availableMethods = fullSet(HttpMethod) - {HttpConnect, HttpTrace}
  test "Multi handler":
    for meth in availableMethods:
      let resp = client.request(root / "/multi/1", httpMethod = meth)
      checkpoint $meth
      if meth in [HttpPost, HttpGet]:
        check resp.code == Http200
      else:
        check resp.code == Http404

  test "Any handler":
    for meth in availableMethods:
      let resp = client.request(root / "/multi/2", httpMethod = meth)
      check resp.code == Http200

  test "Before any handlers with extra before handler":
    let resp = get("/multi/3")
    check:
      resp.body == $HttpGet
      resp.code == Http429

  test "Parameters in definition":
    check get("/multi/4?x=hello").body == "hello"
    check post("/multi/4?x=hello", "").body == "hello"

  test "Having middleware shouldn't cause a 404 to become 200":
    check get("/data/something/other").code == Http404

suite "Streaming":
  test "Chunk response":
    # std/httpclient already supports chunked responses
    let resp = get("/stream/chunked")
    check:
      resp.code == Http200
      resp.headers["Transfer-Encoding"] == "chunked"
      resp.body == "Hello world foo bar "

  test "Server sent events":
    let resp = get("/stream/sse")
    check:
      resp.code == Http200
      resp.headers["Cache-Control"] == "no-store"
      resp.headers["Content-Type"] == "text/event-stream"
    check resp.body == """retry: 3000

data: hello

event: ping
data: pong

event: long
data: hello
data: world

"""

shutdown()
