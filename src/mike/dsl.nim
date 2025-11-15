from std/httpcore import HttpMethod
import router
import macroutils
import httpx
import context
import common
import helpers/context as contextHelpers
import helpers/response as responseHelpers
import errors
import app

when not defined(release):
  import std/terminal

import std/[
    macros,
    asyncdispatch,
    options,
    tables,
    strutils,
    cpuinfo,
    with,
    json,
    strtabs,
    parseutils,
    genasts
]

##[
  This contains the simple old style DSL for writing handlers.
]##

runnableExamples:
  import mike

  "/" -> get:
    ctx.send("Hello world")
##[
  The path can contain special characters to perform more advanced routing. Some examples of this are

  - `"/item/:id"` will match `"/item/9"` and `"/item/hello"` but not `"/item/hello/test"`
  - `"/item/*"` works same as previous example but doesn't store the matched value
  - `"/page/^rest"` will match `"/page/test"` and `"/page/hello/world`" (Basically anything that starts with `"/page/"`). This can only be used at the
    end of a path
]##

var http* = initApp()
  ## Global app instance that we map everything to

macro addMiddleware*(path: static[string], verb: static[HttpMethod], pos: static[HandlerPos], handler: AsyncHandler) =
    ## Adds a middleware to a path
    ## `handType` can be either Pre or Post
    ## This is meant for adding plugins using procs, not adding blocks of code
    # This is different from addHandler since this injects a call
    # to get the ctxKind without the user having to explicitly say
    doAssert pos in {Pre, Post}, "Middleware must be pre or post"
    # Get the type of the context parameter

    result = quote do:
        http.map({HttpMethod(`verb`)}, `path`, HandlerType(`pos`), `handler`)

macro `->`*(path: static[string], info: untyped, body: untyped): untyped =
    ## Defines the operator used to create a handler
    runnableExamples:
      # | The path
      # v
      "/path" -> get: # <-- info section
        # -- Everything after this point is the body
        echo "hello"
    #==#
    let info = getHandlerInfo(path, info, body)

    # Build list of parameters from the info
    var params = @[
      parseExpr"Future[string]"
    ]
    for (name, kind) in info.params:
      params &= newIdentDefs(name, kind)

    # Add the default Context param
    params &= newIdentDefs(ident "ctx", bindSym"Context")

    let prc = newProc(
      params=params,
      body = body,
      pragmas = nnkPragma.newTree(ident"async")
    )

    let
      verbs = info.verbs
      pos = info.pos
      httpSym = bindSym"http"

    result = quote do:
      `httpSym`.map(`verbs`, `path`, `pos`, `prc`)
    echo result.toStrLit

macro `->`*(error: typedesc[CatchableError], info, body: untyped) =
  ## Used to handle an exception. This is used to override the
  ## default handler which sends a [ProblemResponse](mike/errors.html#ProblemResponse)
  runnableExamples:
    import mike
    import std/strformat
    # If a key error is thrown anywhere then this will be called
    KeyError -> thrown:
      ctx.send("The key you provided is invalid")
    # Method dispatch is used, so you can handle parent classes
    # and have it run for all child classes.
    # Be careful catching all errors like this, this means
    # the default error response will be gone
    CatchableError -> thrown:
      ctx.send(fmt"{error[].name} error was thrown")
  #==#
  if info.kind != nnkIdent and not info.eqIdent("thrown"):
    "Verb must be `thrown`".error(info)

proc run*(port: int = 8080, threads: Natural = 0, bindAddr: string = "0.0.0.0") {.gcsafe.} =
    ## Starts the server, should be called after you have added all your routes
    {.gcsafe.}:
      http.run(port, threads, bindAddr)

export asyncdispatch
