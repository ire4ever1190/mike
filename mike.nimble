# Package

version       = "1.3.5"
author        = "Jake Leahy"
description   = "A very simple micro web framework"
license       = "MIT"
srcDir        = "src"

skipDirs = @["tests"]
skipFiles = @["benchmark.nim"]


# Dependencies
requires "nim >= 2.2.4"
requires "zippy >= 0.10.3"
requires "httpx >= 0.3.8"
requires "chronicles >= 0.12.0"

task ex, "Runs the example":
    selfExec "c -f -d:debug -r example"
