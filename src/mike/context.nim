import httpx
import std/[
  with,
  strtabs,
  httpcore,
  asyncdispatch
]

type
  Response* = ref object
    ## Response to a request
    code*: HttpCode
    headers*: HttpHeaders
    body*: string

  ProblemResponse* = ref object
    ## Based losely on [RFC7807](https://www.rfc-editor.org/rfc/rfc7807). Kind (same as type) refers to the name of the
    ## exception and is not a dereferenable URI.
    kind*, detail*: string
    status*: HttpCode

  AsyncHandler* = proc (ctx: Context): Future[string] {.gcsafe.}
    ## Handler for a route

  Context* = ref object of RootObj
    ## Contains all info about the request including the response
    handled*: bool
    response*: Response
    request*: Request
    pathParams*: StringTableRef
    queryParams*: StringTableRef

  SubContext* = concept x
    ## Refers to anything that inheriets Context_
    x is Context

proc newResponse*(): Response =
  ## Creates a new response
  result = Response(
    code: Http200,
    headers: newHttpHeaders(),
    body: ""
  )

proc newContext*(req: Request): Context =
  ## Creates a new context
  result = new Context
  with result:
    handled = false
    request = req
    response = newResponse()
    pathParams = newStringTable()
    queryParams = newStringTable()
