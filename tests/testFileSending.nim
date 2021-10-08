import mike
import asyncdispatch
import utils
import unittest

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

test "Can't read forbidden file":
    check get("/forbidden").code == Http403

