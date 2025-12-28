# TODO, change name
import context, errors, macroutils
import cookies
import bodyParsers/form
import helpers

import std/[
  parseutils,
  httpcore,
  strformat,
  strtabs,
  options,
  jsonutils,
  json,
  strutils,
  macros {.all.},
  typetraits,
  asyncdispatch
]

##[
  Context hooks allow you to automatically parse values from the context. They are also used to send return values.


  Take for example this route
]##
runnableExamples:
  import mike

  "/item/:id" -> get(id: int):
    echo id
##[
  This will automatically parse the path parameter `id` into an `int` and throw an error if it isn't. There are other hooks for headers
  and getting JSON from the body so you likely won't need to write your own. You can implment your own by writing a proc with the following parameters

  * **ctx**: This will be the normal context passed in to allow you to gather values from the request
  * **name**: The name of the parameter
  * **_**: This is just done to specify the type. It looks funky but is needed for implementation reasons

  Here is an example of this for our `CustomType` type
]##
runnableExamples:
  import mike

  type
    CustomType = object

  proc fromRequest*(ctx: Context, name: string, result: out CustomType)=
    # Do processing in here for context
    result = default(CustomType)

  # We can then use that in our handler
  var app = initApp()
  app.get("/custom") do (obj: CustomType):
    echo obj
##[

  All the implemented hooks here support `Option[T]` which make the handler not error if the item cannot be found.
  For example we might want a header to be optional so we could declare it like so
]##
runnableExamples:
  import mike
  import std/options

  "/home" -> get(session: Header[Option[string]]):
    if session.isSome:
      ctx.send "Session specific stuff"
    else:
      ctx.send "Generic stuff"

##[
  If you want the variable names to be different compared to what you are trying to access from the request
  then you can use the `name` pragma.
]##
runnableExamples:
  import mike

  # This will now access the `Authorization` header instead of the `auth` header
  "/people" -> get(auth {.name: "Authorization".}: Header[string]):
    echo auth
    ctx.send "Something"

##[
  ### Form hooks

  When parsing forms you might want to have a custom hook so you can parse types other than basic primitives. This can be done
  with a `fromForm` hook.
]##
runnableExamples:
  import times
  import mike

  proc fromForm(formVal: string, result: out DateTime) =
    result = formVal.parse("yyyy-MM-dd")

  type
    SomeForm = object
      fullName: string
      dob: DateTime # The hook will be called for this

  "/person" -> post(data: Form[SomeForm]):
    echo data

# TODO: Benchmark using some {.cursor.} annotations, might improve performance

type
  ContextHookHandler*[T] = proc (ctx: Context, name: string, val: out T)
    ## A handler generates a value for type T

  BasicType* = SomeNumber | string
    ## Most basic values that are allowed

macro typeName(typ: typedesc): string =
  ## Alias types stick around when `$` is called (e.g. `$Path[int] == "Path[Int]"`)
  ## which causes problems with errors not looking clean. This fixes that
  runnableExamples:
    type Alias[T] = T
    assert int.typeName == "int"
    assert Alias[int].typeName == "int"
  #==#
  let impl = typ.getType()
  if impl.kind == nnkBracketExpr:
    return newLit $impl[1].toStrLit()
  else:
    return newLit $typ.toStrLit()

proc parseNum[T](param: string): T =
  ## Parses an integer/float from a string.
  ## Performs all needed range checks and error throwing
  const typeName = T.typeName

  when T is SomeInteger:
    var val: BiggestInt
    let parsed = param.parseBiggestInt(val)
  elif T is SomeFloat:
    var val: BiggestFloat
    let parsed = param.parseBiggestFloat(val)
  else:
    {.error: $T & " is not supported".}

  if parsed != param.len:
    raise newBadRequestError(fmt"Value '{param}' is not in right format for {typeName}")
  # Perform a range check if the user wants it
  when compileOption("rangechecks"):
    if (typeof(val))(T.low) > val or val > (typeof(val))(T.high):
      raise newBadRequestError(fmt"Value '{param}' is out of range for {$typeName}")
  # Make it become the required number type
  cast[T](val)

#
# Path
#


proc getPathValue*(ctx: Context, name: string, val: out SomeNumber) =
  ## Reads an integer value from the path
  let param = ctx.pathParams[name]
  val = parseNum[typeof(val)](param)

proc getPathValue*(ctx: Context, name: string, val: out string) =
  ## Reads a string value from the path
  val = ctx.pathParams[name]

#
# Headers
#

type
  HeaderTypes* = BasicType | seq[BasicType]
    ## Types that are supported by the header hook

proc basicConversion(inp: string, val: out string) {.inline.} =
  val = inp
proc basicConversion[T: SomeInteger](inp: string, val: out T) {.inline.} =
  val = parseNum[T](inp)


proc getHeaderVal*[T: HeaderTypes](ctx: Context, name: string, val: out Option[T]) =
  ## Tries to read a header from the request. If the header doesn't exist then it returns `none(T)`.
  bind hasHeader
  if hasHeader(ctx, name):
    var rawVal: T
    ctx.getHeader(name).basicConversion(rawVal)
    val = some(rawVal)
  else:
    val = none(T)

proc getHeaderVal*[T: BasicType](ctx: Context, name: string, header: var T) =
  ## Reads a basic type from a header
  var res: Option[T]
  ctx.getHeaderVal(name, res)
  if not res.isSome:
    raise newBadRequestError(fmt"Missing header '{name}' in request")
  header = res.unsafeGet()

proc getHeaderVal[T: seq[BasicType]](ctx: Context, name: string, val: out T) =
  ## Reads a series of values from request headers. This allows reading all values
  ## that have the same header key
  template elemType(): typedesc = typeof(result[0])
  let headers = ctx.getHeaders(name)
  val = newSeq[elementType(default(T))](headers.len)
  for i in 0 ..< headers.len:
    headers[i].basicConversion(val[i])

proc getHeaderHook*(ctx: Context, name: string, result: var auto) {.gcsafe.} =
  bind getHeaderVal
  getHeaderVal(ctx, name, result)


template useCtxHook*(handler: typed) {.pragma.}
  ## Hook to specify how a type should be parsed.
  ## This is a low level proc, more meant for things
  ## that use strange aliases
  ## ```nim check
  ## # Signature of function passed MUST match this
  ## proc someHandler[T](ctx: Context, name: string, result: out T) = result = default(T)
  ##
  ## type SomeAliases[T] {.useCtxHook(someHandler).} = T
  ## ```

macro makeCall(someSym: typed, ctx: Context, name: string, val: out auto) =
  ## Gets around a compiler error when directly calling the sym from `getCustomPragmaVal`
  return newCall(someSym, ctx, name, val)

template getCtxHook*(typ: typed, ctx: Context, name: string, val: out auto) =
  ## Calls the context hook for a type
  bind ourHasCustomPragma
  bind ourGetCustomPragmaVal
  when ourHasCustomPragma(typ, useCtxHook):
    makeCall(ourGetCustomPragmaVal(typ, useCtxHook), ctx, name, val)
  elif compiles(fromRequest(ctx, name, val)):
    fromRequest(ctx, name, val)
  else:
    {.error: "No context hook for `" & $type(typ) & "`".}

#
# Json
#

proc getJsonVal[T](ctx: Context, name: string, result: out T) {.inline.} =
  ## Reads JSON from request. Uses [std/jsonutils](https://nim-lang.org/docs/jsonutils.html) so you can write your own hooks to handle
  ## the parsing of objects
  result = ctx.json(T)

proc getJsonVal[T](ctx: Context, name: string, result: out Option[T]) =
  ## Reads JSON from request. If there is no body then it returns `none(T)`.
  if ctx.hasBody:
    var val: T
    ctx.getJsonVal(name, val)
    result = some(val)
  else:
    result = none(T)

#
# Data
#

proc getContextData[T: ref object](ctx: Context, name: string, result: out T) =
  ## Gets custom data from the context. Throws `500` if the data doesn't exist
  result = ctx[T]
  if result == nil:
    raise newInternalServerError(fmt"Context is missing {$T}")


proc getContextData[T: Option[ref object]](ctx: Context, name: string, result: out T) {.inline.} =
  ## Gets custom data from the context. Doesn't throw any errors if the data doesn't exist
  result = ctx[T]

#
# Form
#

proc fromForm*[T: SomeInteger](formVal: string, result: out T) =
  result = parseNum[T](formVal)

proc fromForm*(formVal: string, result: out string) {.inline.} =
  result = formVal

proc fromForm*(formVal: string, result: out bool) =
  ## Parses boolean. See [parseBool](https://nim-lang.org/docs/strutils.html#parseBool%2Cstring) for what is considered a boolean value
  result = formVal.parseBool()

proc formFromRequest*[T: object | ref object](ctx: Context, name: string, result: out T) =
  ## Converts a form into an object.
  ## Only supports basic objects
  let form = ctx.urlForm
  result = T()
  for key, value in result.fieldPairs():
    if key notin form:
      raise newBadRequestError("'$#' missing in form" % [key])
    var val: typeof(value)
    fromForm(form[key], val)
    value = ensureMove(val)

proc formFromRequest*[T](ctx: Context, name: string, result: out Option[T]) =
  ## Returns none(T) if no form exists at all, if even one key exists then it assumes `some(T)`.
  ## This is because forms are meant to be whole objects.
  if ctx.urlForm.len > 0:
    var val: T
    formFromRequest(ctx, name, val)
    result = some val
  else:
    result = none(T)

#
# Query
#

proc checkQueryExists(ctx: Context, name: string) =
  ## Throws error if `name` isn't a query parameter
  if name notin ctx.queryParams:
    raise newBadRequestError(fmt"'{name}' missing in query parameters")

proc queryFromRequest*[T: SomeNumber](ctx: Context, name: string, result: out T) =
  checkQueryExists(ctx, name)
  result = parseNum[T](ctx.queryParams[name])

proc queryFromRequest*(ctx: Context, name: string, result: out string) =
  checkQueryExists(ctx, name)
  result = ctx.queryParams[name]

proc queryFromRequest*(ctx: Context, name: string, result: out bool) =
  checkQueryExists(ctx, name)
  result = ctx.queryParams[name].parseBool()

proc queryFromRequest*[T](ctx: Context, name: string, result: out Option[T]) =
  if name in ctx.queryParams:
    var val: T
    queryFromRequest(ctx, name, val)
    result = some val
  else:
    result = none(T)

#
# Cookie
#

template parseCookie[T](res: T, value: string) =
  when T is string:
    res = value
  elif T is SomeNumber:
    res = parseNum[T](value)
  else:
    {.error: $typeof(res) & " is not supported for cookies".}

proc cookieFromRequest*[T: BasicType](ctx: Context, name: string, cookie: out T) =
  let cookies = ctx.cookies()

  if name notin cookies:
    raise newBadRequestError(fmt"Cookie '{name}' is missing from request")
  cookie.parseCookie(cookies[name])

proc cookieFromRequest*[T: BasicType](ctx: Context, name: string, result: out Option[T]) =
  let cookies = ctx.cookies()
  if name in cookies:
    var val: T
    val.parseCookie(cookies[name])
    result = some val
  else:
    result = none(T)


# Provide types that specify where in the request to find stuff
# Mostly inspiried by the 5 minutes I glaced at rocket.rs when it was on hacker news (I did quite like it)
type
  Header*[T: HeaderTypes | Option[HeaderTypes]] {.useCtxHook(getHeaderHook).} = T
    ## Specifies that the parameter will come from a header.
    ## If `T` is `seq` and there are no values then it will be empty, an error won't be thrown
  Json*[T] {.useCtxHook(getJsonVal).} = T
    ## Specifies that the parameter is JSON. This gets the JSON from the requests body
    ## and uses [std/jsonutils](https://nim-lang.org/docs/jsonutils.html) for deserialisation
  Data*[T: ref object | Option[ref object]] {.useCtxHook(getContextData).} = T
    ## Get the object from the contexts data
    # ref object is used over RootRef cause RootRef was causing problems
  Path*[T: SomeNumber | string] {.useCtxHook(getPathValue).} = T
    ## Specifies that the parameter should be found in the path.
    ## This is automatically added to parameters that have the same name as a path parameter
  Form*[T] {.useCtxHook(formFromRequest).} = T
    ## Specifies that the parameter is a form.
    ## Currently only supports url encoded forms.
    ## `formForm` can be overloaded for custom parsing of different types
  Query*[T] {.useCtxHook(queryFromRequest).} = T
    ## This means get the parameter from the query parameters sent

  Cookie*[T: BasicType | Option[BasicType]] {.useCtxHook(cookieFromRequest).} = T
    ## Gets a cookie from the request
    # This needs to reparse everytime, think parser is fast enough but not very optimal
    # Could maybe store cookies as custom data like a cache?.

#
# Utils
#

proc fromRequest*(ctx: Context, _: string, result: out Context) {.inline.} =
  ## Enables getting the [Context] parameter inside the request.
  ## Only use this if you know what you are doing, otherwise use ctx hooks
  result = ctx


#
# Response hooks
#

proc sendResponse*(ctx: Context, val: string) =
  ## Sends a string as a response.
  bind send
  if val != "": # Needed while we have the DSL, it doesn't always set the result
    send(ctx, val)

proc sendResponse*[T](ctx: Context, resp: T) =
  ## Generic send hook that delegates to `ctx.send`
  ctx.send(resp)

proc sendResponse*[T: void](ctx: Context, stmt: T) =
  ## Support for routes that return nothing. Just
  ## sends a 200 response
  bind send

proc sendResponse*[T](ctx: Context, fut: Future[T]) {.async.} =
  ## Generic handler for futures, passes it off to a `sendResponse` book that matches for `T`
  ctx.sendResponse(await fut)

export jsonutils
