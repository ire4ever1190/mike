import mike
import utils

import std/unittest

"/item/:id" -> get(id: int):
  ctx.send $id

"/person/:name" -> get(name: string):
  ctx.send name

runServerInBackground()

suite "Path params":
  test "Parse int":
    check get("/item/9").body == "9"

  test "Fails on non integer":
    let resp = get("/item/9.9")
    check:
      resp.code == Http400
      resp.body == "Path value 'id' is not in right format for int"

  test "Parse string":
    check get("/person/me").body == "me"
