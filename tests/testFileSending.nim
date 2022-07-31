import mike
import asyncdispatch
import utils
import unittest
import times
import os

from mike/helpers/context {.all.} import lastModifiedFormat

"/" -> get:
    await ctx.sendFile "readme.md"

"/filedoesntexist" -> get:
    await ctx.sendFile "notafile.html"

"/forbidden" -> get:
    await ctx.sendFile "tests/forbidden.txt"


runServerInBackground()

test "File is sent":
    check get("/").body == $readFile "readme.md"

test "Trying to access non existant file":
    check get("/filedoesntexist").code == Http404

test "Trying to access non existant again":
    check get("/filedoesntexist").code == Http404

test "Getting file that has been modified since":
  let info = getFileInfo("readme.md")
  let resp = get("/", {
    "If-Modified-Since": format(info.lastWriteTime - 1.minutes, lastModifiedFormat, utc())
  })
  check:
    resp.code == Http200
    resp.body == readFile "readme.md"

test "Getting file that hasn't been modified since":
  let info = getFileInfo("readme.md")
  let resp = get("/", {
    "If-Modified-Since": format(info.lastWriteTime + 1.minutes, lastModifiedFormat, utc())
  })
  check:
    resp.code == Http304
    resp.body == ""

when false:
   test "Can't read forbidden file":
       check get("/forbidden").code == Http403

shutdown()
