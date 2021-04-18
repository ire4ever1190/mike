import mike
import httpclient
import unittest
import threadpool
import os
import strformat
import strutils

type PersonCtx = ref object of Context
    name: string

#
# Routing
#

"/" -> get:
    return "index"

"/hello/world" -> get:
    return "foo bar"

"/user/:name" -> get:
    return "Hello " & ctx.pathParams["name"]

"/file/*file" -> get:
    return "Serving file: " & ctx.pathParams["file"]

"/returnformat" -> get:
    let tag = if ctx.queryParams["format"] == "big":
                "h1"
            else:
                "p"
    return fmt"""<{tag}>{ctx.queryParams["text"]}</{tag}>"""

"/uppercase" -> post:
    return ctx.request.body.get().toUpperAscii()

"/person/:name" -> get(ctx: PersonCtx):
    ctx.name = ctx.pathParams["name"]
    return "Hello, " & ctx.name

"/upper/:name" -> beforeGet(ctx: PersonCtx):
    ctx.name = ctx.pathParams["name"].toUpperAscii()

"/upper/:name" -> get(ctx: PersonCtx):
    return "Good evening, " & ctx.name

spawn run()
sleep(100)

let client = newHttpClient()

#
# Methods for accessing server
#

proc get(url: string): httpclient.Response =
    client.request("http://127.0.0.1:8080" & url)

proc post(url: string, body: string): httpclient.Response =
    client.request("http://127.0.0.1:8080" & url, httpMethod = HttpPost, body = body)

#
# Tests
#

suite "GET":
    test "Basic":
        check get("/").body == "index"

    test "404":
        check get("/notfound").code == Http404

    test "Removes trailing slash":
        check get("/hello/world/").body == "foo bar"

    test "Path parameter":
        check get("/user/jake").body == "Hello jake"

    test "Query Parameter":
        check get("/returnformat?format=big&text=hello").body == "<h1>hello</h1>"

    test "Greedy match":
        check get("/file/public/index.html").body == "Serving file: public/index.html"

    test "Stress test": # Test for a nil access error
        for i in 0..1000:
            check get("/").body == "index"


suite "Custom Context":
    test "Basic":
        check get("/person/john").body == "Hello, john"

    test "In middleware":
        check get("/upper/jake").body == "Good evening, JAKE"

   # test "Stress test": # Test for a nil access error
   #     for i in 0..1000:
   #         check get("/upper/hello").body == "Good evening, HELLO"


suite "POST":
    test "Basic":
        check post("/uppercase", "hello").body == "HELLO"
        
quit 0
