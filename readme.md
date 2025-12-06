
![image](https://github.com/ire4ever1190/mike/workflows/Tests/badge.svg)

[Docs](https://ire4ever1190.github.io/mike/mike.html)

Simple framework that I use for all my personal projects. Mostly used for writing small API's and website

### Quick overview

Just create an app then add your routes

```nim
var app = initApp()

# Fully typed handlers
app.get("/home") do () -> string:
  "hello"
    
"/mike" -> post:
  ctx.send("Teapot", Http427)
```

You can specify before/after handlers by prefixing the verb

```nim
# You get information via typing your proc
app.beforeGet("/^path") do (path: string):
  # Log all requests that happen
  echo path
```

Has seen in the examples the `ctx` variable is used which is an implicit variable that allows you to
access everything about the request and specify what the response will be.

### Context hooks

A nice feature of Mike that sets it apart from other Nim frameworks is support for context hooks
that allow you to add parameters to your routes that get information for you and handle if its missing

```nim
"/some/route" -> post(x: Header[string], data: Json[SomeObject], page: Query[int]) ->
    # Do stuff with parameters here
```

You can make your own context hooks to do anything from load some json to getting a database connection from a pool
