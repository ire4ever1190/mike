# TODO, change name
import context, errors

import bodyParsers/form

import std/[
  parseutils,
  httpcore,
  strformat,
  strtabs,
  options,
  jsonutils,
  json,
  strutils
]

##[
  Context hooks allow you to automatically parse values from the context by setting parameters in the route definition.
  Take for example this route
]##
runnableExamples:
  import mike

  "/item/:id" -> get(id: int):
    echo id
##[
  This will automatically parse the path parameter `id` into an `int` and throw an error if it isn't. There are other hooks for headers
  and getting JSON from the body so you likely won't need to write your own. You can though by writing a proc with a signature like so
]##
runnableExamples:
  import mike
  type
    CustomType = object
  proc fromRequest*[T: CustomType](ctx: Context, name: string, _: typedesc[T]): T =
    # Do processing in here for context
    discard
##[
  * **ctx**: This will be the normal context passed in to allow you to gather values from the request
  * **name**: The name of the parameter
  * **_**: This is just done to specify the type. It looks funky but is needed for implementation reasons
]##

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

# TODO: Benchmark using some {.cursor.} annotations, might improve performance



# Provide types that specify where in the request to find stuff
# Mostly inspiried by the 5 minutes I glaced at rocket.rs when it was on hacker news (I did quite like it)
type
  BasicType* = SomeNumber | string
    ## Most basic values that are allowed
  Path*[T: SomeNumber | string] = object
    ## Specifies that the parameter should be found in the path
  Form*[T] = object
    ## Specifies that the parameter is a form.
    ## Currently only supports url encoded forms.
    ## `formForm` can be overloaded for custom parsing of different types
  Query*[T] = object
    ## Specifies that the parameter is a query parameter
  Json*[T] = object
    ## Specifies that the parameter is JSON
  HeaderTypes* = BasicType | seq[BasicType]
    ## Types that are supported by the header hook
  Header*[T: HeaderTypes | Option[HeaderTypes]] = object
    ## Specifies that the parameter will come from a header.
    ## If `T` is `seq` and there are no values then it will be empty, an error won't be thrown
  Data*[T: ref object | Option[ref object]] = object
    ## Get the object from the contexts data
    # ref object is used over RootRef cause RootRef was causing problems

#
# Utils
#


proc parseIntImpl[T](param: string): T =
  ## Parses an integer/float from a string.
  ## Performs all needed range checks and error throwing
  when T is SomeInteger:
    var val: BiggestInt
    let parsed = param.parseBiggestInt(val)
  elif T is SomeFloat:
    var val: BiggestFloat
    let parsed = param.parseBiggestFloat(val)
  else:
    {.error: $T & " is not supported".}

  if parsed != param.len:
    raise newBadRequestError(fmt"Value '{param}' is not in right format for {$T}")
  # Perform a range check if the user wants it
  when compileOption("rangechecks"):
    if (typeof(val))(T.low) > val or val > (typeof(val))(T.high):
      raise newBadRequestError(fmt"Value '{param}' is out of range for {$T}")
  # Make it become the required number type
  cast[T](val)

#
# Path
#


proc fromRequest*[T: SomeNumber](ctx: Context, name: string, _: typedesc[Path[T]]): T =
  ## Reads an integer value from the path
  let param = ctx.pathParams[name]
  parseIntImpl[T](param)

proc fromRequest*(ctx: Context, name: string, _: typedesc[Path[string]]): string =
  ## Reads a string value from the path
  result = ctx.pathParams[name]

#
# Headers
#

proc fromRequest*[T: BasicType](ctx: Context, name: string, _: typedesc[Header[T]]): T =
  ## Reads a basic type from a header
  if not ctx.hasHeader(name):
    raise newBadRequestError(fmt"Missing header '{name}' in request")
  let headerValue = ctx.getHeader(name)
  when T is SomeNumber:
    result = parseIntImpl[T](headerValue)
  elif T is string:
    result = headerValue

proc fromRequest*[T: seq[BasicType]](ctx: Context, name: string, _: typedesc[Header[T]]): T =
  ## Reads a series of values from request headers. This allows reading all values
  ## that have the same header key
  template elemType(): typedesc = typeof(result[0])
  for header in ctx.getHeaders(name):
    when elemType() is SomeNumber:
      result &= parseIntImpl[elemType()](header)
    elif elemType() is string:
      result &= header

proc fromRequest*[T: Option[HeaderTypes]](ctx: Context, name: string, _: typedesc[Header[T]]): T =
  ## Tries to read a header from the request. If the header doesn't exist then it returns `none(T)`.
  if ctx.hasHeader(name):
    result = some ctx.fromRequest(name, Header[T.T])

#
# Json
#

proc fromRequest*[T](ctx: Context, name: string, _: typedesc[Json[T]]): T {.inline.} =
  ## Reads JSON from request. Uses `std/jsonutils` so you can write your own hooks to handle
  ## the parsing of objects (See [std/jsonutils](https://nim-lang.org/docs/jsonutils.html))
  result = ctx.json(T)

proc fromRequest*[T](ctx: Context, name: string, _: typedesc[Json[Option[T]]]): Option[T] =
  ## Reads JSON from request. If there is no body then it returns `none(T)`.
  if ctx.hasBody:
    result = some ctx.fromRequest(name, Json[T])

#
# Data
#

proc fromRequest*[T: RootRef](ctx: Context, name: string, _: typedesc[Data[T]]): T =
  ## Gets custom data from the context. Throws `500` if the data doesn't exist
  result = ctx[T]
  if result == nil:
    raise newInternalServerError(fmt"Context is missing {$T}, could be due to missing precondition serverside")


proc fromRequest*[T: Option[ref object]](ctx: Context, name: string, _: typedesc[Data[T]]): T {.inline.} =
  ## Gets custom data from the context. Doesn't throw any errors if the data doesn't exist
  result = ctx[T]


#
# Form
#

proc fromForm*[T: SomeInteger](ctx: Context, name: string, _: typedesc[Form[T]], form: URLEncodedForm): T =
  result = parseIntImpl[T](form[name])

proc fromForm*(ctx: Context, name: string, _: typedesc[Form[string]], form: URLEncodedForm): string =
  result = form[name]

proc fromForm*(ctx: Context, name: string, _: typedesc[Form[bool]], form: URLEncodedForm): bool =
  ## Parses boolean. See [parseBool](https://nim-lang.org/docs/strutils.html#parseBool%2Cstring) for what is considered a boolean value
  result = form[name].parseBool()

proc fromRequest*[T: object | ref object](ctx: Context, name: string, _: typedesc[Form[T]]): T =
  ## Converts a form into an object
  let form = ctx.urlForm
  for key, value in result.fieldPairs():
    if key notin form:
      raise newBadRequestError("'$#' missing in form" % [key])
    value = fromForm(ctx, key, Form[typeof(value)], form)

proc fromRequest*[T](ctx: Context, name: string, _: typedesc[Form[Option[T]]]): Option[T] =
  ## Returns none(T) if no form exists at all, if even one key exists then it assumes `some(T)`.
  ## This is because forms are meant to be whole objects.
  if ctx.urlForm.len > 0:
    return some fromRequest(ctx, name, Form[T])

#
# Query
#

proc checkQueryExists(ctx: Context, name: string) =
  ## Throws error if `name` isn't a query parameter
  if name notin ctx.queryParams:
    raise newBadRequestError(fmt"'{name}' missing in query parameters")


proc fromRequest*[T: SomeNumber](ctx: Context, name: string, _: typedesc[Query[T]]): T =
  checkQueryExists(ctx, name)
  result = parseIntImpl[T](ctx.queryParams[name])

proc fromRequest*(ctx: Context, name: string, _: typedesc[Query[string]]): string =
  checkQueryExists(ctx, name)
  result = ctx.queryParams[name]

proc fromRequest*(ctx: Context, name: string, _: typedesc[Query[bool]]): bool =
  checkQueryExists(ctx, name)
  result = ctx.queryParams[name].parseBool()

proc fromRequest*[T](ctx: Context, name: string, _: typedesc[Query[Option[T]]]): Option[T] =
  if name in ctx.queryParams:
    result = some fromRequest(ctx, name, Query[T])

export jsonutils
