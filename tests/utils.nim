import httpclient
import threadpool
import os
import mike
import std/exitprocs
import std/uri
import json

let client* = newHttpClient()

const root* = "http://127.0.0.1:8081".parseUri()

proc get*(url: string, headers: openArray[(string, string)] = []): httpclient.Response =
    client.request(root / url, headers = newHttpHeaders(headers))

proc head*(url: string, headers: openArray[(string, string)] = []): httpclient.Response =
    client.request(root / url, headers = newHttpHeaders(headers), httpMethod = HttpHead)

proc post*(url: string, body: string): httpclient.Response =
    client.request(root / url, httpMethod = HttpPost, body = body)

proc post*[T](url: string, body: T): httpclient.Response =
  url.post($ %* body)

proc put*(url: string, body: string): httpclient.Response =
  client.request(root / url, httpMethod = HttpPut, body = body)

proc to*[T](resp: httpclient.Response, t: typedesc[T]): T =
  resp.body.parseJson().to(t)

template stress*(body: untyped) =
    ## Nil access errors (usually with custom ctx) would not show up unless I made more than a couple requests
    for i in 0..1000:
        body

proc `==`*(a, b: HttpHeaders): bool =
  result = true
  for k in a.table.keys:
    if a[k] != b[k]:
      return false
  for k in b.table.keys:
    if a[k] != b[k]:
      return false

template runServerInBackground*() =
    ## Starts the server on a seperate thread
    bind spawn
    bind sleep
    spawn run(port=8081)
    sleep(100)

proc test*(app: var App, body: (proc (base: URI, client: AsyncHttpClient) {.async.})) =
  # Create a future we can use to wait until the server has started
  let start = newFuture[void]()
  app.onStart() do ():
    start.complete()

  # Start server
  asyncCheck app.runAsync(8080)
  waitFor start

  # Startup was flakey without this, think there is some extra events that need to run
  waitFor sleepAsync 0

  # Now we can run the body since the server has started
  let client = newAsyncHttpClient()
  defer: client.close()
  waitFor body(parseUri("http://127.0.0.1:8080"), client)

template shutdown*() =
    ## Quits with the current test result
    quit getProgramResult()

export httpclient
export uri
