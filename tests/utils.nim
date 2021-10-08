import httpclient
import threadpool
import os
let client = newHttpClient()

proc get*(url: string): httpclient.Response =
    client.request("http://127.0.0.1:8080" & url)

proc post*(url: string, body: string): httpclient.Response =
    client.request("http://127.0.0.1:8080" & url, httpMethod = HttpPost, body = body)

template stress*(body: untyped) =
    ## Nil access errors (usually with custom ctx) would not show up unless I made more than a couple requests
    for i in 0..1000:
        body
        
template runServerInBackground*() =
    bind spawn
    bind sleep
    spawn run()
    sleep(100)

export httpclient
