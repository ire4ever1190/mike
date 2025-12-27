import mike
import std/[httpclient, uri, unittest, segfaults]

var app = initApp()

app.get("/async") do () -> Future[string] {.async.}:
  await sleepAsync(10)
  "hello"


proc tests() {.async.} =
  let client = newAsyncHttpClient()
  defer: client.close()
  const base = parseUri("http://127.0.0.1:8080")

  asyncCheck app.runAsync()

  test "Can call async route":
    check client.get(base / "async").await().body.await() == "hello"

waitFor tests()
