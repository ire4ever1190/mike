## Extra errors that can be used.
## These errors contain pre set status codes so you don't need to handle them.
##
## The functions work as constructors for exceptions
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


template makeErrorConstructor*(name: untyped, code: HttpCode) =
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
  type `name Error`* = object of HttpError
  proc `name Error`*(msg: string): ref HttpError {.inline.} =
    result = (ref `name Error`)(msg: msg, status: code)

makeErrorConstructor(NotFound, Http404)
makeErrorConstructor(UnAuthorised, Http401)
makeErrorConstructor(Forbidden, Http403)

export httpcore
