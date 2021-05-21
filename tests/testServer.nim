import mike
import httpclient
import unittest
import threadpool
import os
import strformat
import strutils
import std/json

type PersonCtx = ref object of Context
    name: string

type Frog = object
    colour: string

#
# Routing
#

"/" -> get:
    return "index"

"/hello/world" -> get:
    result = "foo bar"

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

"/person/:name" -> beforeGet(ctx: PersonCtx):
    ctx.name = ctx.pathParams["name"]

"/person/:name" -> get(ctx: PersonCtx):
    return "Hello, " & ctx.name

"/upper/:name" -> beforeGet(ctx: PersonCtx):
    ctx.name = ctx.pathParams["name"].toUpperAscii()

"/another" -> beforeGet(ctx: PersonCtx):
    ctx.name = "human"
    ctx.response.body = "another "

"/another" -> get:
    ctx.response.body &= "one"

"/another" -> afterGet(ctx: PersonCtx):
    check ctx.name == "human"

"/upper/:name" -> get(ctx: PersonCtx):
    return "Good evening, " & ctx.name

"/helper/json" -> get:
    ctx.json = Frog(colour: "green")

"/helper/sendjson" -> get:
    ctx.send(Frog(colour: "green"))

"/form" -> get:
    let form = ctx.parseForm()
    ctx.send(form["hello"])

"/form" -> post:
    let form = ctx.parseForm()
    ctx.send(form["hello"] & " " & form["john"])

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

template stress(body: untyped) =
    ## Nil access errors (usually with custom ctx) would not show up unless I made more than a couple requests
    for i in 0..1000:
        body

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

suite "Forms":
    test "URL encoded form GET":
        check get("/form?hello=world&john=doe").body == "world"

    test "URL encoded form POST":
        check post("/form", "hello=world&john=doe").body == "world doe"

quit 0
