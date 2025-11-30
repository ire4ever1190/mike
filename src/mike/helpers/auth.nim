##[
  Implements some basic functions for working with authentication
]##

import ../errors
import ../context
import std/strutils
import std/strscans
import std/base64
import std/options
import std/parseutils

const
  authHeader = "Authorization"
  challengeHeader = "WWW-Authenticate"

type
  Authorization = ref object of RootObj
    ## Building block for more complex authentication schemes
    username*: string

  AuthScheme* = distinct string
    ## See [authentication scheme](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Authorization#directives) for possible values

proc authScheme*(ctx: Context): Option[string] =
  ## Returns the [authentication scheme](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Authorization#directives) used
  if not ctx.hasHeader(authHeader):
    return
  let authHeader = ctx.getHeader(authHeader)
  var res: string
  let parsedLength = authHeader.parseUntil(res, ' ')
  if parsedLength != authHeader.len:
    return some res

func `$`*(x: AuthScheme): string {.inline.} = x.string

proc fromRequest*[T: AuthScheme](ctx: Context, name: string, result: out Option[T]) =
  let scheme = ctx.authScheme
  result = if scheme.isSome: some AuthScheme(scheme.unsafeGet())
           else: none(T)

proc fromRequest*[T: AuthScheme](ctx: Context, name: string, result: out T) =
  ## Gets auth scheme from requests. Raises exception if no header passed or empty scheme
  var scheme: Option[T]
  ctx.fromRequest(name, scheme)
  if scheme.isNone:
    raise newBadRequestError("No Authorization header sent")
  result = scheme.unsafeGet()
  if result.string.isEmptyOrWhitespace:
    raise newUnAuthorisedError("No auth scheme provided")

proc basicAuthDetails*(ctx: Context, realm = "Enter details"): tuple[username, password: string] =
  ## Gets authentication details sent with basic auth.
  ## to check that the user has sent something. Use this over [basicAuth] if you want to check details against your own user list
  runnableExamples:
    import mike

    "/user/login" -> get:
      let (username, password) = ctx.basicAuthDetails()
      # We can now go into the DB and check if username matches password
  #==#
  if not ctx.hasHeader(authHeader):
    ctx.setHeader(challengeHeader, "Basic realm=" & realm)
    raise newUnAuthorisedError("You are not authenticated with HTTP basic")
  let authHeader = ctx.getHeader(authHeader)
  # Get the details from the header
  var details: string
  if not authHeader.scanf("$sBasic$s$+", details):
    raise newBadRequestError("Authorization header is malformed")
  # Now the decode the base64 string which is username:password
  if not details.decode().scanf("$*:$*", result.username, result.password):
    raise newBadRequestError("Details must be in username:password form that is base64 encoded")


proc basicAuth*(ctx: Context, username, password: string,
                realm = "Enter details"): Authorization =
  ## Returns true if the user is authenticated with [HTTP Basic auth](https://developer.mozilla.org/en-US/docs/Web/HTTP/Authentication#basic_authentication_scheme). If they aren't then it sends back a challenge to authenticate.
  ## Use [basicAuthDetails] if you want to manually check if a username and password line up
  runnableExamples:
    import mike

    "/admin" -> get:
      discard ctx.basicAuth("admin", "superPassword")
      # If code gets to this point then the user is properly authenticated
  #==#
  let (provUser, provPass) = ctx.basicAuthDetails(realm)
  if username != provUser or password != provPass:
    ctx.setHeader(challengeHeader, "Basic realm=" & realm)
    raise newUnAuthorisedError("Your provided details are incorrect")
  return Authorization(username: username)

proc bearerToken*(ctx: Context): string =
  ## Returns the bearer token sent in the request
  if not ctx.hasHeader(authHeader):
    raise newUnAuthorisedError("You are not authenticated with HTTP bearer token")

  let authHeader = ctx.getHeader(authHeader)

  if not authHeader.scanf("$sBearer$s$+", result):
    raise newBadRequestError("Authorization header is not in bearer format")
