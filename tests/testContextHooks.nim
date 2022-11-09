import mike
import utils

import std/[
  unittest,
  json,
  httpclient,
  strformat
]

"/item/:id" -> get(id: int8):
  ctx.send $id

"/person/:name" -> get(name: string):
  ctx.send name

"/headers/1" -> get()

runServerInBackground()

proc errorMsg(x: httpclient.Response): string =
  x.body.parseJson()["detail"].getStr()

suite "Path params":
  test "Parse int":
    check get("/item/9").body == "9"

  test "Fails on non integer":
    let resp = get("/item/9.9")
    let json = resp.body.parseJson()
    check:
      resp.code == Http400
      json["kind"].getStr() == "BadRequestError"
      json["detail"].getStr() == "Path value '9.9' is not in right format for int8"

  test "Fails when to large":
    let highVal = $(int8.high.int + 1)
    let resp = get("/item/" & highVal)
    check:
      resp.code == Http400
      resp.errorMsg == fmt"Path value '{highVal}' is out of range for int8"

  test "Parse string":
    check get("/person/me").body == "me"
