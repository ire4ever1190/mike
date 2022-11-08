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

  Routing
  =======

  Routing is done via `"path" -> verb: body` sytax
]##
runnableExamples "-r:off":
  "/hello" -> get:
    # `ctx` is an implicit variable that provides access to the
    # request/response
    ctx.send "Hello!"

  run() # This starts the server

## Parameters can be specified in the verb to change the context variable (and provide type safe parameter access in future)
runnableExamples:
  "/hello" -> get(c: Context):
    # Our context variable is now `c`
    c.send "Hello!"

##[
  Paths can have special parameters specified to allow more advanced routing

  - `:param`: Matches a part and stores in param
  - `*`: Matches an entire part (A part is /between/ slashes)
  - `^param`: Matches the rest of the path no matter what in stores in param
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

  "/file/^path" -> get:
    ctx.sendFile ctx.pathParams["path"]

##[
  Error handling
  --------------

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
  type CustomException = object of CatchableException

  CustomException -> thrown:
    ctx.send "Custom exception got thrown"

  "/index" -> get:
    # ...
    raise (ref CustomException)(msg: "You won't see this")
    # ...

##[
  Responding
  ==========
]##

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
