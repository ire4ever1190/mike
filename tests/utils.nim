import httpclient
import threadpool
import os
import mike
import std/exitprocs
import std/uri
import json

let client* = newHttpClient()

const root* = "http://127.0.0.1:8080".parseUri()

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
    spawn run()
    sleep(100)

template shutdown*() =
    ## Quits with the current test result
    quit getProgramResult()

export httpclient
export uri
