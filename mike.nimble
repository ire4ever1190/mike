# Package

version       = "0.1.0"
author        = "Jake Leahy"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.4.2"
requires "httpx >= 0.2.4"
requires "websocketx >= 0.1.2"

task ex, "Runs the example":
    exec "nim c -f --gc:orc -r example"
