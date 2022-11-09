import std/[genasts, macros, strutils]

## Extra errors that can be used.
## These errors contain pre set status codes so you don't need to handle them
##
## You should use the constructors so that the status codes match up to the name
runnableExamples:
  try:
    raise NotFoundError("Could not find something")
  except HttpError as e:
    assert e.status == Http404

import std/httpcore

type
  HttpError* = object of CatchableError
    ## Like normal error except it has a status assoicated with it
    ## which is used instead of normal 400 status when thrown
    status*: HttpCode


macro makeErrorConstructor*(name: untyped, code: HttpCode): untyped =
  ## Use this to make your own constructor for a status code.
  ## Also makes a new type which inherits [HttpError]
  runnableExamples:
    makeErrorConstructor(Teapot, 418)
    try:
      raise TeapotError("I'm a teapot")
    except HttpError as e:
      assert e.status == Http418
      assert e.msg == "I'm a teapot"
  #==#
  # "Why is this done with a macro? This very clearly only needs a macro!"
  # Yes that is true, but templates were making raise statements have invalid names for some reason

  if name.kind != nnkIdent:
    "Name should be an identifier".error(name)
  let
    fullName = name.strVal & "Error"
    procname = "new" & fullName

  result = genAst(name = ident(fullName), procName = ident(procName), code):
    type name* = object of HttpError
    proc procName*(msg: string): ref name {.inline.} = (ref name)(msg: msg, status: code)

makeErrorConstructor(BadRequest, Http400)
makeErrorConstructor(UnAuthorised, Http401)
makeErrorConstructor(Forbidden, Http403)
makeErrorConstructor(NotFound, Http404)
