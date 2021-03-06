# Package

version       = "1.1.0"
author        = "Jake Leahy"
description   = "A very simple micro web framework"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.4.2"
requires "httpx >= 0.2.4"
requires "websocketx >= 0.1.2"

task ex, "Runs the example":
    exec "nim c -f -d:debug -r example"

task tests, "Runs tests with both normal and orc gc":
    exec "nimble test"
    exec "nimble -d:orc test"
