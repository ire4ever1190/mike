## Extra errors that can be used

import std/httpcore

type
  HttpError* = object of CatchableError
    ## Like normal error except it has a status assoicated with it
    ## which is used instead of normal 400 status when thrown
    status*: HttpCode

  UnauthorisedError* = object of CatchableError
    ## Should be raised when user is trying to access something that they don't have access to


  InvalidContentError* = object of CatchableError
    ## Should be raised when user is sending a request with invalid content type


template makeErrorConstructor(name: untyped, code: HttpCode) =
  proc `name Error`*(msg: string): ref HttpError {.inline.} =
    result = (ref HttpError)(msg: msg, status: code)

makeErrorConstructor(NotFound, Http404)
