# Joins all the tests into one file. Makes tests run a lot faster
import macros
import os
import strutils


macro importTests() =
  result = newStmtList()
  for (kind, file) in walkDir("tests/", relative = true):
    if kind == pcFile and file.startsWith("test") and file.endsWith(".nim") and file != "tester.nim":
      result &= nnkImportStmt.newTree(file.replace(".nim", "").ident)

importTests()
