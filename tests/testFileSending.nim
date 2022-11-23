import mike
import asyncdispatch
import utils
import unittest
import times
import os
import osproc
import std/sysrand
import std/strutils
import std/strformat

import pkg/zippy

from mike/helpers/context {.all.} import lastModifiedFormat, maxReadAllBytes

"/" -> [get, head]:
  await ctx.sendFile "readme.md"

"/filedoesntexist" -> [get, head]:
    await ctx.sendFile "notafile.html"

"/forbidden" -> [get, head]:
    await ctx.sendFile "tests/forbidden.txt"

"/testFile" -> [get, head]:
    let file = ctx.getHeader("filePath")
    await ctx.sendFile(file, dir = "tests/", allowRanges = true)


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

proc makeLargeFile() =
  # Create a random test file that is 10 mb in size.
  # Saves needing to store it in the git repo
  if not fileExists("tests/random.dat"):
    "tests/random.dat".writeFile(urandom(maxReadAllBytes))

test "Large files are streamed":
  # We can test this since streaming doesn't support compression
  # So if we request compression and it isn't compressed, then we know
  # it was streamed
  makeLargeFile()
  let resp = get("/testFile", {"filePath": "random.dat"})
  # echo respBody
  check resp.headers["Content-Length"].parseBiggestInt() == maxReadAllBytes
  assert resp.body == readFile("tests/random.dat")
  check resp.body.len == maxReadAllBytes
  check not resp.headers.hasKey("Content-Encoding")

test "Large files aren't sent with HEAD":
  makeLargeFile()
  let
    getResp = get("/testFile", {"filePath": "random.dat"})
    headResp = head("/testFile", {"filePath": "random.dat"})
  check:
    headResp.body == ""
    headResp.headers == getResp.headers

test "Range request":
  makeLargeFile()
  const
    start = 1234
    finish = 5678
    size = (finish - start) + 1 # Since its inclusive of start byte
  let resp = get("/testFile", {
    "filePath": "random.dat",
    "Range": fmt"bytes={start}-{finish}"
  })
  check resp.code == Http206
  check:
    resp.headers["Content-Range"] == fmt"bytes {start}-{finish}/{maxReadAllBytes}"
    resp.body.len == size
    resp.headers["Content-Length"] == $size
    resp.body == "tests/random.dat".readFile()[start..finish]

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
      resp.code == Http200
      resp.headers["Content-Encoding"] == "deflate"
      resp.body.uncompress(dfDeflate) == readmeFile

  test "Chooses first possible":
    let resp = get("/", {
      "Accept-Encoding": "br;q=1.0, gzip;q=0.8, *;q=0.1"
    })
    check:
      resp.headers["Content-Encoding"] == "gzip"
      resp.body.uncompress(dfGzip) == readmeFile

  test "Works with HEAD":
    let
      headers = {
        "Accept-Encoding": "br;q=1.0, gzip;q=0.8, *;q=0.1"
      }
      getResp = get("/", headers)
      headResp = head("/", headers)
    check:
      headResp.code == Http200
      getResp.headers == headResp.headers

test "Check against curl":
  let (body, exitCode) = execCmdEx("curl -s --compressed http://127.0.0.1:8080/")
  check:
    exitCode == 0
    body == readmeFile

when false:
   test "Can't read forbidden file":
       check get("/forbidden").code == Http403

shutdown()
