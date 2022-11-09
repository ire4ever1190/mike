# TODO, change name
import context, errors
import std/[
  tables,
  parseutils,
  httpcore,
  strformat,
  strtabs
]

type
    Path*[T: SomeNumber | string] = distinct T
      ## Specifies that the parameter should be found in the path
    Form*[T: object | ref object] = object
      ## Specifies that the parameter is a form
    Json*[T: object | ref object] = object
      ## Specifies that the parameter is JSO


template pathRangeCheck(val: BiggestInt | BiggestFloat, T: typedesc[Path]) =
  ## Perfoms range check if range checks are turned on.
  ## Sends back 400 telling client they are out of range
  when compileOption("rangechecks"):
    if (typeof(val))(T.low) > val or val > (typeof(val))(T.high):
      raise newBadRequestError(fmt"Path value '{param}' is out of range for {$T}")

proc fromRequest*[T: SomeInteger | SomeFloat](ctx: Context, name: string, _: typedesc[Path[T]]): T =
  ## Reads an integer value from the path
  let param = ctx.pathParams[name]
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

proc fromRequest*(ctx: Context, name: string, _: typedesc[Path[string]]): string =
  ## Reads a string value from the path
  result = ctx.pathParams[name]



