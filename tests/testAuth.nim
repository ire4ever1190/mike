import mike
import utils

import std/[
  unittest,
  json,
  httpclient,
  strformat,
  strutils,
  base64,
  httpcore
]

"/basic" -> get():
  ctx.basicAuth("foo", "bar")
  ctx.send "Hello authenticated user"

runServerInBackground()

suite "Basic":
  proc authHeader(username, password: string): seq[(string, string)] =
    result = @{"Authorization": "Basic " & encode(username & ":" & password)}
  test "No header 401":
    let resp = get("/basic")
    check resp.code == Http401
    check resp.headers["WWW-Authenticate"] == "Basic realm=Enter details"

  test "Bad header 400":
    check get("/basic", {"Authorization": "B"}).code == Http400

  test "Malformed header 400":
    check get("/basic", {"Authorization": "Basic " & encode("userpass")}).code == Http400

  test "Invalid username 401":
    let resp = get("/basic", authHeader("f", "bar"))
    check resp.code == Http401
    check resp.headers["WWW-Authenticate"] == "Basic realm=Enter details"

  test "Invalid password 401":
    let resp = get("/basic", authHeader("foo", "b"))
    check resp.code == Http401
    check resp.headers["WWW-Authenticate"] == "Basic realm=Enter details"

  test "Valid credentials":
    let resp = get("/basic", authHeader("foo", "bar"))
    check resp.code == Http200
    check not resp.headers.hasKey("WWW-Authenticate")
    check resp.body == "Hello authenticated user"
