import mike
import mike/middlewares/cors
import ./utils
import std/[
  unittest,
  httpcore,
  strutils
]

# Create app and configure CORS with specific origins and settings
var app = initApp()
app.addCORS(
  origins = ["http://localhost:8080", "https://example.com"],
  methods = {HttpGet, HttpPost, HttpPut},
  headers = ["Content-Type", "X-Custom-Header"],
  credentials = true,
  exposeHeaders = ["X-Custom-Header"],
  maxAge = 10.minutes
)

app.get("/cors/test") do () -> string:
  "CORS test successful"

app.post("/cors/test") do () -> string:
  "POST CORS test successful"

app.test() do (base: URI, client: AsyncHttpClient) {.async.}:
  suite "CORS":
    test "Simple Request (Valid Origin)":
      let resp = await client.request(base / "cors/test", HttpGet, headers = newHttpHeaders {
        "Origin": "http://localhost:8080"
      })

      check:
        resp.code == Http200
        resp.body.await() == "CORS test successful"
        resp.headers["Access-Control-Allow-Origin"] == "http://localhost:8080"
        resp.headers["Access-Control-Allow-Credentials"] == "true"
        resp.headers["Access-Control-Expose-Headers"] == "X-Custom-Header"
        resp.headers["Vary"] == "Origin"

      # Preflight-only headers should NOT be present on simple requests
      check:
        not resp.headers.hasKey("Access-Control-Allow-Methods")
        not resp.headers.hasKey("Access-Control-Allow-Headers")
        not resp.headers.hasKey("Access-Control-Max-Age")

    test "Preflight Request (Valid Origin)":
      let resp = await client.request(base / "cors/test", HttpOptions, headers = newHttpHeaders {
        "Origin": "https://example.com",
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "Content-Type"
      })
      checkpoint $resp.headers
      check:
        resp.code == Http200
        resp.headers["Access-Control-Allow-Origin"] == "https://example.com"
        resp.headers["Access-Control-Allow-Methods"].string.contains("GET")
        resp.headers["Access-Control-Allow-Methods"].string.contains("POST")
        resp.headers["Access-Control-Allow-Methods"].string.contains("PUT")
        resp.headers["Access-Control-Allow-Methods"].string.contains("OPTIONS")
        resp.headers["Access-Control-Allow-Headers"] == "Content-Type, X-Custom-Header"
        resp.headers["Access-Control-Max-Age"] == "600"
        resp.headers["Vary"] == "Origin"
        resp.headers["Access-Control-Allow-Credentials"] == "true"
        resp.headers["Access-Control-Expose-Headers"] == "X-Custom-Header"

    test "Unauthorized Origin (Failing Origin)":
      let resp = await client.request(base / "cors/test", HttpGet, headers = newHttpHeaders {
        "Origin": "http://malicious.com"
      })

      check:
        resp.code == Http200
        resp.body.await() == "CORS test successful"
        # Access-Control-Allow-Origin should NOT be present for unauthorized origins
        not resp.headers.hasKey("Access-Control-Allow-Origin")
        # Vary header should still be present
        resp.headers["Vary"] == "Origin"
        # Other CORS headers may still be present (middleware runs regardless)
        resp.headers["Access-Control-Allow-Credentials"] == "true"
        resp.headers["Access-Control-Expose-Headers"] == "X-Custom-Header"
