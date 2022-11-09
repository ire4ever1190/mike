# TODO, change name
import context, errors
import std/[
  tables,
  parseutils,
  httpcore,
  strformat
]

type
    Path*[T: SomeNumber | string] = distinct T
      ## Specifies that the parameter should be found in the path
    Form*[T: object | ref object] = object
      ## Specifies that the parameter is a form
    Json*[T: object | ref object] = object
      ## Specifies that the parameter is JSO


template pathRangeCheck[X](val: BiggestInt | BiggestFloat, T: typedesc[Path[X]]) =
  ## Perfoms range check if range checks are turned on.
  ## Sends back 400 telling client they are out of range
  when compileOption("rangechecks"):
    if (typeof(val))(T).low > val or val > (typeof(val))(T).high:
      raise BadRequestError(fmt"{val} is out of range for {X}")

proc fromRequest*[T: SomeInteger](ctx: Context, name: string, value: var Path[T]) =
  ## Reads an integer value from the context
  # We don't check if the name exists since the user shouldn't be assigning Path[T] parameters
  # themselves. In future if we allow renaming then might need to add in checks
  var val: BiggestInt
  ctx.pathParams[name].parseBiggestInt(val)
  pathRangeCheck(val)
  value = cast[T](val)

