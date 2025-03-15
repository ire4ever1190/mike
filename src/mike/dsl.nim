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

var http = initApp()
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
        http.addHandler(`path`, HttpMethod(`verb`), HandlerType(`pos`), `handler`)

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
      parseExpr"string | void" # Small optimisation to remove string, might need to remove
    ]
    for param in info.params:
      params &= newIdentDefs(ident param.name, param.kind)

    let prc = newProc(
      params=params,
      body = body
    )

    result = genAst(path = info.path, verbs = info.verbs, pos = info.pos, prc):
        addHandler(path, verbs, pos, prc)

func noAsyncMsg(input: sink string): string {.inline.} =
  ## Removes the async traceback from a message
  discard input.parseUntil(result, "Async traceback:")

method handleRequestError*(error: ref Exception, ctx: Context) {.base, async.} =
  ## Base handler for handling errors. Use `<Exception> -> thrown`
  ## instead of writing the method out yourself.
  # If user has already provided an error status then use that
  let code = if error[] of HttpError: HttpError(error[]).status
             elif ctx.status.int in 400..599: ctx.status
             else: Http400
  # Send the details
  ctx.send(ProblemResponse(
    kind: $error[].name,
    detail: error[].msg.noAsyncMsg(),
    status: code
  ), code)

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
      mikeRouter.rearrange()
    when compileOption("threads"):
        # Use all processors if the user has not specified a number
        var threads = if threads > 0: threads else: countProcessors()
    echo "Started server \\o/ on " & bindAddr & ":" & $port
    let settings = initSettings(
        Port(port),
        bindAddr = bindAddr,
        numThreads = threads
    )
    run(onRequest, settings)

export asyncdispatch
