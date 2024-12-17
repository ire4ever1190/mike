# Package

version       = "1.3.5"
author        = "Jake Leahy"
description   = "A very simple micro web framework"
license       = "MIT"
srcDir        = "src"

skipDirs = @["tests"]
skipFiles = @["benchmark.nim"]


# Dependencies
requires "nim >= 1.6.12"
requires "zippy >= 0.10.3"
requires "httpx >= 0.3.7"

task ex, "Runs the example":
    selfExec "c -f -d:debug -r example"
