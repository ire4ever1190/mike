#
# Used to run benchmarks to check that code isn't creating slowdowns.
# Also does other utility functions like generating graphs and basic statistics over past runs
#
import std/osproc
import std/os
import std/strformat
import std/times

const gc = when defined(useOrc): "orc" else: "refc"

const
    buildCmd = fmt"nim c -d:release -d:lto --gc:{gc} -o:benchserver example.nim" # Command to build server
    benchCmd = "wrk http://127.0.0.1:8080/" # Run wrk to benchmark server

case paramStr(1):
    of "compile":
        # Compile the benchmark server, should only be done once per code change
        echo execProcess buildCmd
    of "bench":
        # Run wrk and saves output to file in benchmark/ with UNIX
        # timestamp as it's name
        if not fileExists "benchserver":
            echo "Compile the bench server first"
            quit 1
        let serverProcess = startProcess "./benchserver"
        sleep 100 # Give server time to boot
        discard existsOrCreateDir("benchmark/")
        ("benchmark/" & $getTime().toUnix()).writeFile execProcess benchCmd
        serverProcess.close()
    else:
        echo "Invalid option: ", paramStr(1)