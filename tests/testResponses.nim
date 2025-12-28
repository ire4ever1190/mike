import mike
import ./utils
import std/[httpclient, uri, unittest]

var app = initApp()

app.get("/async") do () -> Future[string] {.async.}:
  await sleepAsync(10)
  "hello"

app.get("/async/void") do () {.async.}:
  discard

app.test() do (base: URI, client: AsyncHttpClient) {.async.}:
  test "Can call async route":
    check client.get(base / "async").await().body.await() == "hello"

  test "Void async works":
    check client.get(base / "async" / "void").await().code == Http200
