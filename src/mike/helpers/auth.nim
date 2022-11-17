##[
  Implements some basic functions for working with authentication
]##

import ../errors
import ../context
import std/strscans
import std/base64

const
  authHeader = "Authorization"
  challengeHeader = "WWW-Authenticate"

type
  Authorization = ref object of RootObj
    ## Building block for more complex authentication schemes
    username*: string

proc basicAuth*(ctx: Context, username, password: string,
                realm = "Enter details"): Authorization =
  ## Returns true if the user is authenticated with [HTTP Basic auth](https://developer.mozilla.org/en-US/docs/Web/HTTP/Authentication#basic_authentication_scheme). If they aren't then it sends back a challenge to authenticated.
  runnableExamples:
    import mike

    "/admin" -> get:
      discard ctx.basicAuth("admin", "superPassword")
      # If code gets to this point then the user is properly authenticated
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
  var provUser, provPass: string
  if not details.decode().scanf("$*:$*", provUser, provPass):
    raise newBadRequestError("Details must be in username:password form that is base64 encoded")
  if username != provUser or password != provPass:
    ctx.setHeader(challengeHeader, "Basic realm=" & realm)
    raise newUnAuthorisedError("Your provided details are incorrect")
  return Authorization(username: username)
