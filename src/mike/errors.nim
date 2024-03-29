import std/[genasts, macros]

## Extra errors that can be used.
## These errors contain pre set status codes so you don't need to handle them
##
## You should use the constructors so that the status codes match up to the name
runnableExamples:
  try:
    raise newNotFoundError("Could not find something")
  except HttpError as e:
    assert e.status == Http404

import std/httpcore

type
  HttpError* = object of CatchableError
    ## Like normal error except it has a status assoicated with it
    ## which is used instead of normal 400 status when thrown
    status*: HttpCode

  ProblemResponse* = object
    ## Based losely on [RFC7807](https://www.rfc-editor.org/rfc/rfc7807). Kind (same as type) refers to the name of the
    ## exception and is not a dereferenable URI.
    kind*, detail*: string
    status*: HttpCode

macro makeErrorConstructor*(name: untyped, code: HttpCode): untyped =
  ## Use this to make your own constructor for a status code.
  ## Also makes a new type which inherits [HttpError]
  runnableExamples:
    makeErrorConstructor(Teapot, Http418)
    try:
      raise newTeapotError("I'm a teapot")
    except HttpError as e:
      assert e.status == Http418
      assert e.msg == "I'm a teapot"
  #==#
  # "Why is this done with a macro? This very clearly only needs a template!"
  # Yes that is true, but templates were making `raise` make the exception name literally be "nameError"

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
makeErrorConstructor(RangeNotSatisfiable, Http416)
makeErrorConstructor(InternalServer, Http500)

export httpcore

