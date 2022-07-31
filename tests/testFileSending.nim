import mike
import asyncdispatch
import utils
import unittest
import times
import os
import osproc

import pkg/zippy

# from mike/helpers/context {.all.} import lastModifiedFormat
# Since {.all.} isn't on 1.4 I need to do this
const lastModifiedFormat = "ddd',' dd MMM yyyy HH:mm:ss 'GMT'"

"/" -> get:
    await ctx.sendFile "readme.md"

"/filedoesntexist" -> get:
    await ctx.sendFile "notafile.html"

"/forbidden" -> get:
    await ctx.sendFile "tests/forbidden.txt"


runServerInBackground()

let readmeFile = readFile("readme.md")

test "File is sent":
    check get("/").body == readmeFile

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
    resp.body == readmeFile

test "Getting file that hasn't been modified since":
  let info = getFileInfo("readme.md")
  let resp = get("/", {
    "If-Modified-Since": format(info.lastWriteTime, lastModifiedFormat, utc())
  })
  check:
    resp.code == Http304
    resp.body == ""

test "Server compresses when client allows":
  let resp = get("/", {
    "Accept-Encoding": "gzip, deflate"
  })
  check:
    resp.headers["Content-Encoding"] == "gzip"
    resp.body.uncompress() == readmeFile

test "Check against curl":
  let (body, exitCode) = execCmdEx("curl -s --compressed http://127.0.0.1:8080/")
  check:
    exitCode == 0
    body == readmeFile

when false:
   test "Can't read forbidden file":
       check get("/forbidden").code == Http403

shutdown()
