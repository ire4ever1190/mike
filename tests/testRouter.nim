import mike/router
import unittest
import tables
import strutils
import random
import times
# import nimprof


template benchmark(benchmarkName: string, code: untyped) =
  block:
    let t0 = epochTime()
    code
    let elapsed = epochTime() - t0
    let elapsedStr = elapsed.formatFloat(format = ffDecimal, precision = 3)
    echo "CPU Time [", benchmarkName, "] ", elapsedStr, "s"

proc randomString(length: int = 10): string =
    for i in 0..<length:
        result &= char(rand(int('A') .. int('z'))) 

var testTrie = newTrie[string]()

test "Adding data to trie":
    testTrie["hello world"] = "hi"


test "Getting data from trie":
    check testTrie["hello world"] == "hi"

test "Adding similar text":
    testTrie["hello all"] = "goodbye"
    check testTrie["hello all"] == "goodbye"
    check testTrie["hello world"] == "hi"

test "Adding disimilar text":
    testTrie["no thanks"] = "hello"
    check testTrie["no thanks"] == "hello"
    check testTrie["hello world"] == "hi"

test "Match any":
    testTrie["/user/:id/test"] = "hello"
    check testTrie["/user/37161/test"] == "hello"

    # Check that two parameters are allowed
    testTrie["/user/:id/:date/end"] = "h"
    check testTrie["/user/777/01011970/end"] == "h"

    # Check that parameters can be at the end
    testTrie["/user/:id"] = "6"
    check testTrie["/user/3761"] == "6"

    # Check that a static route and parameter route can coexist
    testTrie["/account/:id"] = "student"
    testTrie["/account/all"] = "everybody"

    # check testTrie["/account/alll"] == "student" # This edgecase is being left out
    check testTrie["/account/4"] == "student"
    check testTrie["/account/all"] == "everybody"

    # Check that the child node is not overwritten
    testTrie["/courses/:id/delete"] = "DELETED"
    testTrie["/courses/:id/update"] = "UPDATED"
    
    check testTrie["/courses/5/delete"] == "DELETED"
    check testTrie["/courses/5/update"] == "UPDATED"

# test "URL parameter parsing":
    # testTrie["/student/:name"] = "John"
    # echo testTrie["/student/jacob"].urlParameters
    # check testTrie["/student/jacob"].urlParameters["name"] == "jacob"
    
test "Error handling":
    try:
        discard testTrie["there is nothing"]
        check false
    except KeyError:
        check true
    
test "Benchmark between table and trie":
    var testTable = initTable[string, string]()
    var routes: seq[string]
    for route in "tests/testRoutes.txt".lines:
        var route = route.replace(":", "")
        testTable[route] = "Foo Bar"
        testTrie[route] = "Foo Bar"
        routes &= route

    let n = 500000
    benchmark "Trie":
        for i in 0..n:
            discard testTrie[sample(routes)]

    benchmark "Hash Table":
        for i in 0..n:
            discard testTable[sample(routes)]
