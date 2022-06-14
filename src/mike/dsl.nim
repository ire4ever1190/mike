from context      import AsyncHandler
from std/httpcore import HttpMethod
import router
import macroutils
import httpx
import middleware
import context
import response
import common
import std/[
    macros,
    macrocache,
    asyncdispatch,
    options,
    tables,
    uri,
    strutils,
    strformat,
    cpuinfo,
    with
]

runnableExamples:
  "/" -> get:
    ctx.send("Hello world")


type 
    # Runtime information about route
    Route = ref object
        handler: AsyncHandler
        context: proc (): Context
        conequal: proc (x: Context): bool

var mikeRouter = Router[Route]()


proc newContext*[T: SubContext](): Context =
  result = new T

proc isSame*[T: SubContext](o: Context): bool =
  result = o of T

proc addHandler(path: string, ctxKind: typedesc[SubContext], verb: HttpMethod, pos: HandlerPos, handler: AsyncHandler) =
    ## Adds a handler to the routing IR
    var route = Route(handler: handler)
    bind newContext
    if $ctxKind != "Context":
      route.context = newContext[ctxKind]
      route.conequal = isSame[ctxKind]
    mikeRouter.map(verb, path, route, pos)
      

macro addMiddleware*(path: static[string], verb: static[HttpMethod], pos: static[HandlerPos], handler: AsyncHandler) =
    ## Adds a middleware to a path
    ## `handType` can be either Pre or Post
    ## This is meant for adding plugins using procs, not adding blocks of code
    # This is different from addHandler since this injects a call
    # to get the ctxKind without the user having to explicitly say
    doAssert pos in {Pre, Post}, "Middleware must be pre or post"
    # Get the type of the context parameter
    let ctxKind = ident $handler.getImpl().params[1][1] # Desym the type

    result = quote do:
        addHandler(`path`, `ctxKind`, HttpMethod(`verb`), HandlerType(`pos`), `handler`)


macro createFullHandler*(path: static[string], httpMethod: HttpMethod, pos: HandlerPos,
                         handler: untyped, parameters: varargs[typed] = []): untyped =
    ## Does the needed AST transforms to add needed parsing code to a handler and then
    ## to add that handler to the routing tree. This call also makes the parameters be typed
    ## so that more operations can be performed on them
    let handlerProc = handler.createAsyncHandler(path, parameters.getParamPairs())
    var contextType = ident"Context"

    # Check if custom context type was passed
    for parameter in parameters.getParamPairs():
      if parameter.kind.super().eqIdent("Context"):
        contextType = parameter.kind
        break
    # Now do the final addHandler call to get the generated proc added to the 
    # router
    result = quote do:
        addHandler(`path`, `contextType`, HttpMethod(`httpMethod`), HandlerPos(`pos`), `handlerProc`)
  
macro `->`*(path: static[string], info: untyped, body: untyped): untyped =
    ## Defines the operator used to create a handler
    ## context info is the info about the route e.g. get or get(c: Context)
    runnableExamples:
        "/home" -> get:
            ctx.send "You are home"
    let info = getHandlerInfo(path, info, body)

    # Send the info off to another call to symbol bind the parameters
    result = newCall(
        bindSym "createFullHandler",
        newLit info.path,
        newLit HttpMethod(info.verb),
        newLit HandlerPos(info.pos),
        body
    )
    for param in info.params:
        result &= newLit param.name
        result &= param.kind
    
template send404() =
    ctx.response.body = "Not Found =("
    ctx.response.code = Http404
    req.respond(ctx) 
    req.send()

func move(src, ctx: var Context) =
  ## move and copies the variables from the source context into the target context
  with ctx:
      handled = src.handled
      request = move src.request
      response = move src.response

proc onRequest(req: Request): Future[void] {.async.} =
  {.gcsafe.}:
    if req.path.isSome() and req.httpMethod.isSome():
        var found = false
        var contexts = @[req.newContext()]
        for routeResult in mikeRouter.route(req.httpMethod.get(), req.path.get()):   
          found = true 
          var ctx: Context
          let hasCustomCtx = routeResult.handler.context != nil
          if not hasCustomCtx:
            ctx = contexts[0]
          else:
            var lookingFor = routeResult.handler.conequal
            for c in contexts:
              if lookingFor(c):
                ctx = c
                break
            if ctx == nil: 
              let newCtx = routeResult.handler.context() 
              contexts &= newCtx
              ctx = newCtx
            contexts[0].move(ctx)
            
          ctx.pathParams = routeResult.pathParams
          ctx.queryParams = routeResult.queryParams
          
          var body = await routeResult.handler.handler(ctx)
          # Really wanna remove this whole can return a string thing
          if body != "":
            ctx.response.body = body
          if hasCustomCtx:
            ctx.move(contexts[0])
        if not found:
          req.send("Not Found =(", code = Http404)
        elif not contexts[0].handled:
          req.respond(contexts[0])
          
    else:
      req.send(body = "This request is malformed")





proc run*(port: int = 8080, threads: Natural = 0) {.gcsafe.} =
    ## Starts the server, should be called after you have added all your routes
    runnableExamples "-r:off":
      "/hello" -> get:
        ctx.send "Hello World!"
      run()
    #==#
    {.gcsafe.}:
      mikeRouter.rearrange()
    when compileOption("threads"):
        # Use all processors if the user has not specified a number
        var threads = if threads > 0: threads else: countProcessors()
    echo "Started server \\o/ on 127.0.0.1:" & $port
    let settings = initSettings(
        Port(port),
        numThreads = threads
    )
    run(onRequest, settings)
