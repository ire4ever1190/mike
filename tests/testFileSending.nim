import mike
import asyncdispatch
import utils
import unittest
import times
import os
import osproc

import pkg/zippy

from mike/helpers/context {.all.} import lastModifiedFormat

"/" -> get:
    await ctx.sendFile "readme.md"

"/filedoesntexist" -> get:
    await ctx.sendFile "notafile.html"

"/forbidden" -> get:
    await ctx.sendFile "tests/forbidden.txt"

"/testFile" -> get:
    let file = ctx.getHeader("filePath")
    await ctx.sendFile(file, dir = "tests/")


runServerInBackground()

let
  readmeFile = readFile("readme.md")
  thisFile = readFile("tests/testFileSending.nim")

test "File is sent":
    check get("/").body == readmeFile

test "Trying to access non existant file":
    check get("/filedoesntexist").code == Http404

test "Trying to access non existant again":
    check get("/filedoesntexist").code == Http404

suite "Files inside different directory":
  test "Trying to access file at base directory":
    check get("/testFile", {"filePath": "testFileSending.nim"}).body == thisFile

  test "Trying to access file outside of base directory":
    check get("/testFile", {"filePath": "../.gitignore"}).code == Http403

test "Getting file that has been modified since":
  let info = getFileInfo("readme.md")
  let resp = get("/", {
    "If-Modified-Since": inZone(info.lastWriteTime - 1.minutes, utc()).format(lastModifiedFormat)
  })
  check:
    resp.code == Http200
    resp.body == readmeFile

test "Getting file that hasn't been modified since":
  let info = getFileInfo("readme.md")
  let resp = get("/", {
    "If-Modified-Since": info.lastWriteTime.inZone(utc()).format(lastModifiedFormat)
  })
  check:
    resp.code == Http304
    resp.body == ""

suite "Compression":
  test "gzip":
    let resp = get("/", {
      "Accept-Encoding": "gzip, deflate"
    })
    check:
      resp.headers["Content-Encoding"] == "gzip"
      resp.body.uncompress() == readmeFile

  test "deflate":
    let resp = get("/", {
      "Accept-Encoding": "deflate"
    })
    check:
      resp.headers["Content-Encoding"] == "deflate"
      resp.body.uncompress(dfDeflate) == readmeFile

  test "Chooses first possible":
    let resp = get("/", {
      "Accept-Encoding": "br;q=1.0, gzip;q=0.8, *;q=0.1"
    })
    check:
      resp.headers["Content-Encoding"] == "gzip"
      resp.body.uncompress(dfGzip) == readmeFile

test "Check against curl":
  let (body, exitCode) = execCmdEx("curl -s --compressed http://127.0.0.1:8080/")
  check:
    exitCode == 0
    body == readmeFile

when false:
   test "Can't read forbidden file":
       check get("/forbidden").code == Http403

shutdown()
