## This module contains middleware for configuring logging via [chronicles](https://github.com/status-im/nim-chronicles).
##
## In development, I recommend using the block sink via by compiling with `-d:chronicles_sinks=textblocks`. This makes the
## exception messages more readable

import ../[app, context, errors]
import ../helpers/request

import std/[asyncdispatch, uri]

import pkg/[httpx, chronicles]

proc pathAndQuery(uri: sink Uri): string =
  ## Returns the path and query combined
  if uri.query != "":
    return uri.path & "?" & uri.query
  uri.path

proc addLogging*(app: var App) =
  ## Enables logging with the app.
  app.beforeEach do (ctx: Context) {.async.}:
    debug "Starting request", meth=ctx.httpMethod, path = $ctx.url

  app.afterEach do (ctx: Context, err: ref Exception) {.async.}:
    # Log any errors. If its a HttpError then we only consider 5xx to be worthy of error
    if err != nil and (not (err of HttpError) or (ref HttpError)(err).status.is5xx):
      error "Request failed", path = $ctx.url, staus=ctx.response.code, error = $err.name, msg=err.msg, trace=err.getStackTrace()
    else:
      info "Request finished", meth=ctx.httpMethod, code=ctx.response.code, path = $ctx.url
