import httpx
import std/[
  with,
  strtabs,
  httpcore,
  asyncdispatch,
  options
]

type
  Response* = ref object
    ## Response to a request
    code*: HttpCode
    headers*: HttpHeaders
    body*: string

  AsyncHandler* = proc (ctx: Context): Future[string] {.gcsafe.}
    ## Handler for a route

  Context* = ref object of RootObj
    ## Contains all info about the request including the response
    handled*: bool
    response: Response
    request*: Request
    pathParams*: StringTableRef
    queryParams*: StringTableRef
    data: seq[RootRef]

  WriteCtxBody* = object of RootEffect
    ## Effect when writing to the context result

proc response*(x: Context): var Response {.tags: [WriteCtxBody].} =
  ## Returns writeable body for the response
  x.response

proc contains*[T: RootRef](ctx: Context, data: typedesc[T]): bool =
  ## Returns true if `T` is in the context
  runnableExamples:
    type
      Auth = ref object of RootObj
      JWT = ref object of Auth

    var ctx = Context()
    ctx &= Auth()
    # It has auth but we never set a JWT so it doesn't have that
    assert Auth in ctx
    assert JWT notin ctx
  #==#
  for d in ctx.data:
    if d of T:
      return true

proc add*[T: RootRef](ctx: Context, data: T) =
  ## Adds `data` into the context. It must be unique i.e. `setData` cannot be called with two instances of `T` (Use [replace] if you want to overwrite the data)
  runnableExamples:
    var ctx = Context()
    type Auth = ref object of RootObj
    ctx &= Auth()
    doAssertRaises(AssertionDefect):
      ctx &= Auth()
  #==#
  assert T notin ctx, $T & " has already been set for the context"
  ctx.data &= data



proc replace*[T: RootRef](ctx: Context, data: T) =
  ## Replaces `data` in context if its found. Adds normally if not found
  var found = false
  for d in ctx.data.mitems:
    if d of T:
      d = data
      found = true
  if not found:
    ctx.data &= data

proc `[]`*[T: RootRef](ctx: Context, _: typedesc[T]): T =
  ## Gets the value of custom data stored in a context
  runnableExamples:
    import mike
    type
      Account = ref object of RootObj
        balance: int
        id: string

    "/^path" -> beforeGet:
      if ctx.hasHeader("accountID"):
        # Just create default account. This could instead be loaded
        # from the database
        ctx &= Account(
          balance: 9,
          id: ctx.getHeader("accountID")
        )

    "/account" -> get:
      let data = ctx[Account]
      if data != nil:
        ctx.send "Hello " & data.id
      else:
        ctx.send(Http404)
  #==#
  for d in ctx.data:
    if d of T:
      return T(d)

proc `[]`*[T: Option[ref object]](ctx: Context, _: typedesc[T]): T =
  ## Gets the value of custom data stored in a context. If the data
  ## cannot be found then `none(T)` is returned
  runnableExamples:
    import mike
    type
      Account = ref object of RootObj
        balance: int
        id: string

    # There are no before handlers to add the data so it
    # will always return none
    "/accounts" -> get:
      let p = ctx[Option[Account]]
      if p.isNone:
        ctx.send "This account isn't here"
      else:
        ctx.send "Hello " & p.get().id
  #==#
  let d = ctx[T.T]
  if d != nil:
    result = some d

proc newResponse*(): Response =
  ## Creates a new response
  result = Response(
    code: Http200,
    headers: newHttpHeaders(titleCase=true),
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
