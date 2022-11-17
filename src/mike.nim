import std/options
import std/asyncdispatch
import std/strtabs
import std/httpcore

import mike/[
  dsl,
  context,
  helpers,
  ctxhooks,
  errors,
  public
]


import mike/bodyParsers/[
    form,
    multipart
]

import httpx

##[
  Mike is a small framework meant for building small applications. I made it for my personal projects (that are usually
  just an API with simple web interface) so expect it to be opininated.

  # Getting Started

  To get started add the dependency `mike#fd2da8c` to your nimble file or run `nimble install mike@#fd2da8c"`. If that
  all worked then you can test out some of the next examples to check it all works

  # Routing

  You specify all your routes using`"path" -> verb: body` sytax and then use [run](mike/dsl.html#run%2Cint%2CNatural) to start the server.
  All verbs [supported by Nim](https://nim-lang.org/docs/httpcore.html#HttpMethod) can be used
]##
runnableExamples "-r:off":
  "/hello" -> get:
    # `ctx` is an implicit variable that provides access to the
    # request/response
    ctx.send "Hello!"

  "/data" -> post:
    echo ctx.body

  run() # This starts the server. You can specify the port

## On top of them you can also prefix your verb with `before`/`after` to have them run before or after your normal handlers.
## Unlike normal handlers, you can specify multiple handlers to handle the same route. If an exception is thrown then the chain
## of handlers stops running
runnableExamples:
  # Order of declaration doesn't matter
  "/something" -> beforeGet:
    echo "Handler that runs before main handler"

  "/something" -> get:
    echo "Main handler for /something"

  "/something" -> afterGet:
    echo "Handler that runs after main handler"

##[
  Paths can be more than static and can allow for parameters or wildcards

  - `:param`: Matches a part and stores in param
  - `*`: Matches an entire part
  - `^param`: Matches the rest of the path no matter what in stores in param (This can only be at the end)

  If it stores a parameter then it can be accessed through `pathParams`
]##

runnableExamples:
  "/person/:id" -> get:
    ctx.send "Person has ID " & ctx.pathParams["id"]

  # More contrained matches are matched first
  "/person/admin" -> get:
    ctx.send "This is the admin"

  # /delete/<anything here>/something would match
  "/delete/*/something" -> delete:
    ctx.send "I will delete that"

  "/^something" -> get: # This will run before every GET request
    echo "[GET] ", ctx.pathParams["path"]

  "/file/^path" -> get:
    await ctx.sendFile ctx.pathParams["path"]

##[
  ## Parameters

  Routes can also have parameters which allow you to change the name of the implicit `ctx` variable but also to add type safety
  for getting information from a request.

  The `ctx` variable can be changed by simply making another variable of type `Context`
]##

runnableExamples:
  "/" -> get(notCtx: Context):
    notCtx.send "Hello world"

##[
  Type safe parameters are done with request hooks which are [described in more depth here](mike/ctxhooks.html) but we will also
  go over basic usage here. The parameters are specified like normal parameters in Nim and call a function relating to the type
  when the route is matched. There are hooks for headers, path parameters, query parameters, etc built into Mike but you can easily create
  your own to provide something like a database connection handler
]##

runnableExamples:
  import std/options
  # If there is a path parameter with the same name then it is automatically
  # converted to Path[T]
  "/account/:id" -> get(id: int): # id is Path[int] which is basically int
    ctx.send "Account has ID: " & $id

  "/admin" -> get(token: Header[string]):
    if token == "secretValue":
      echo "Admin stuff"

  # By default an error will be thrown if the value is missing
  # But you can make it Option[T] so it wont error
  "/search" -> get(query: Query[Option[string]]):
    let queryVal = query.get("everything")

##[
  # Context

  The variable `ctx` seen in the examples is an implicit variable of type [Context](mike/context.html#Context) and is used for both forming
  the responses and getting information from the request

  ## Responding

  Responding is mostly done through `send` overloads but extra data such as headers can also be set through the context. If you don't explicitly call
  send but have still modified the response through the context then it will automatically send it at the end
]##
runnableExamples:
  "/extraheaders" -> get:
    # You can set headers
    ctx.setHeader("key", "value")
    # We don't call send explicitly but Mike will still send the header

    # Headers can have multiple values associated with them
    ctx.addHeader("key", "Another value")

  type
    Person = object
      name: string
      age: int

  "/json" -> get:
    let resp = Person(name: "John Doe", age: 42)
    # send has overloads but context itself also has some setters
    # which means you can either send the JSON or just add it to the
    # response while you add other stuff
    ctx.json = resp # This just sets the response but doesn't send it
    ctx.send(resp)  # This sends the response which means you are done
    # Both cases have correct headers set
##[
  See helpers for full list of the functions available

  ## Recieving

  Context also has getters and functions for getting information about the request.
]##
runnableExamples:
  import std/json

  "/anything" -> post:
    echo "The client has sent ", ctx.body
  type
    Person = object
      name: string
      age: int

  "/json" -> post:
    let json: JsonNode = ctx.json
    # There is also a helper for converting it
    let person = ctx.json(Person)

##[
  ## Custom data

  To allow passing data through all of a context handlers (before - main - after) Mike has a feature called Custom data
  that allows you to add extra info to the request that can be accessed later. This can be used for storing session data about a request,
  connection to the database, or really anything. The objects just need to inherit from `RootObj`
]##
runnableExamples:
  type
    # Our custom object just needs to inherit from RootObj
    Session = ref object of RootObj
      name: string
      doNotTrack: bool

  "/^path" -> beforeGet(doNotTrack {.name: "DNT".}: Header[string]):
    let session = Session(
      name: "Bob",
      doNotTrack: doNotTrack == "1"
    )
    # We can then add it to the context like so
    ctx &= session

  "/some/page" -> get():
    # We can now get the data back since this is running
    # after the before handler
    let session = ctx[Session]
    if session.doNotTrack:
      echo "Turning off mega spyware...."
    else:
      echo "Spying on every pixel the user looks at"

##[
  # Error handling


  By default if an exception is thrown in the program and doesn't have a handler associated with it then a JSON object
  like this (See [ProblemResponse](mike/errors.html#ProblemResponse))

  ```nim
    {
      "kind": "ExceptionName",
      "detail": "Message from exception",
      "status": 400
    }
  ```

  This default behaviour can be overridden for certain exceptions using the `thrown` verb
]##
runnableExamples:
  type CustomException = object of CatchableError

  CustomException -> thrown:
    ctx.send "Custom exception got thrown"

  "/index" -> get:
    # ...
    raise (ref CustomException)(msg: "You won't see this")
    # ...

export asyncdispatch
export strtabs
export httpx
export options

export context
export dsl
export helpers
export form
export multipart
export ctxhooks
export httpcore
export errors
export public
