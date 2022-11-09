# TODO, change name
import context, errors
import std/[
  tables,
  parseutils,
  httpcore,
  strformat,
  strtabs
]

##[
  Context hooks allow you to automatically parse values from the context by setting parameters in the route definition.
  Take for example this route
]##
runnableExamples:
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

# TODO: Benchmark using some {.cursor.} annotations, might improve performance



# Provide types that specify where in the request to find stuff
# Mostly inspiried by the 5 minutes I glaced at rocket.rs when it was on hacker news (I did quite like it)
type
  BasicType* = SomeNumber | string
    ## Most basic values that are allowed
  Path*[T: SomeNumber | string] = distinct T
    ## Specifies that the parameter should be found in the path
  Form*[T: object | ref object] = object
    ## Specifies that the parameter is a form
  Json*[T: object | ref object] = object
    ## Specifies that the parameter is JSO
  Header*[T: BasicType | seq[BasicType]] = distinct T

template pathRangeCheck(val: BiggestInt | BiggestFloat, T: typedesc[Path]) =
  ## Perfoms range check if range checks are turned on.
  ## Sends back 400 telling client they are out of range
  when compileOption("rangechecks"):
    if (typeof(val))(T.low) > val or val > (typeof(val))(T.high):
      raise newBadRequestError(fmt"Path value '{param}' is out of range for {$T}")

template parseIntImpl(param: string) =
  when T is SomeInteger:
    var val: BiggestInt
    let parsed = param.parseBiggestInt(val)
  else:
    # Does anyone use floats in paths?
    var val: BiggestFloat
    let parsed = param.parseBiggestInt(val)
  if parsed != param.len:
    raise newBadRequestError(fmt"Path value '{param}' is not in right format for {$T}")
  pathRangeCheck(val, Path[T])
  result = cast[T](val)

proc fromRequest*[T: SomeInteger | SomeFloat](ctx: Context, name: string, _: typedesc[Path[T]]): T =
  ## Reads an integer value from the path
  let param = ctx.pathParams[name]
  parseIntImpl(param)

proc fromRequest*(ctx: Context, name: string, _: typedesc[Path[string]]): string =
  ## Reads a string value from the path
  result = ctx.pathParams[name]

proc fromRequest*[T: BasicType](ctx: Context, name: string, _: typedesc[Header[T]]): T =
  ## Reads a basic type from a header
  if not ctx.hasHeader(name):
    raise newBadRequestError(fmt"Missing header '{name}' in request")
  let headerValue = ctx.getHeader(name)

