import mike
import macros
import threadpool
import os
import httpclient
import unittest
import segfaults
import exitprocs

group("posts") do:
    post:
        return "post created"
    get:
        return "posts"

# Big example
group("api") do:
    get("home") do:
       return "you are home"

    group("/user") do:
        post:
            return "new user created"
        get:
            return "john"

    group "posts":
        get("newest") do:
            return "latest post"

        get("all") do:
            return "list of posts"

spawn run()
sleep(100)
let client = newHttpClient()

#
# Methods for accessing server
#

proc get(url: string): httpclient.Response =
    client.request("http://127.0.0.1:8080" & url)

proc post(url: string, body: string = ""): httpclient.Response =
    client.request("http://127.0.0.1:8080" & url, httpMethod = HttpPost, body = body)

suite "Basic example":
    test "GET":
        check get("/posts").body == "posts"
    test "POST":
        check post("/posts", "").body == "post created"

test "one verb for one route":
    check get("/api/home").body == "you are home"

test "routes under":
    check get("/api/posts/all").body == "list of posts"
    check get("/api/posts/newest").body == "latest post"

test "Multiple verbs for one route":
    check get("/api/user").body == "john"
    check post("/api/user").body == "new user created"

quit getProgramResult()
