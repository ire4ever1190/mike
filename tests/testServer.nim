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
  options
]



type PersonCtx* = ref object of Context
    name*: string


type Frog = object
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

"/person/:name" -> beforeGet(ctx: PersonCtx):
    ctx.name = ctx.pathParams["name"]

"/person/:name" -> get(ctx: PersonCtx):
    return "Hello, " & ctx.name

"/another" -> beforeGet(ctx: PersonCtx):
  ctx.name = "human"
  ctx.response.body = "another "

"/another" -> get:
    ctx.response.body &= "one"

"/another" -> afterGet(ctx: PersonCtx):
  assert ctx.name == "human"

"/upper/:name" ->  beforeGet(ctx: PersonCtx):
    ctx.name = ctx.pathParams["name"].toUpperAscii()

"/upper/:name" -> get(ctx: PersonCtx):
    return "Good evening, " & ctx.name

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

"/file" -> get:
  ctx.setHeader("Cache-Control", "public, max-age=432000")
  await ctx.sendFile(ctx.queryParams["file"])

"/keyerror" -> get:
  raise (ref KeyError)(msg: "Should be overridden")

"/genericerror" -> get:
  raise (ref Exception)(msg: "Something failed")

"/shoulderror" -> beforeGet:
  raise (ref Exception)(msg: "Something failed")

"shoulderror" -> get:
  ctx.send("This shouldn't send")

KeyError -> thrown:
  ctx.send("That key doesn't exist")

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

suite "Custom Context":
  test "Basic":
    check get("/person/john").body == "Hello, john"

  test "In middleware":
    check get("/upper/jake").body == "Good evening, JAKE"

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
    let 
      client = newHttpClient()
      resp = client.request("http://127.0.0.1:8080/file?file=mike.nimble")
    check resp.body == "mike.nimble".readFile()
    check resp.headers["Content-Type"] == "text/nimble"
    check resp.headers["Cache-Control"] == "public, max-age=432000"

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

shutdown()
