## Extra errors that can be used

type
  UnauthorisedError* = object of CatchableError
    ## Should be raised when user is trying to access something that they don't have access to

  NotFoundError* = object of CatchableError
    ## Should be raised when user is trying to access something that doesn't exist or cannot be found

  InvalidContentError* = object of CatchableError
    ## Should be raised when user is sending a request with invalid content type