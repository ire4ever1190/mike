## This module contains middleware for configuring logging via [chronicles](https://github.com/status-im/nim-chronicles).
##
## In development, I recommend using the block sink via by compiling with `-d:chronicles_sinks=textblocks`. This makes the
## exception messages more readable

import ../[app, context]
import ../helpers/request

import std/[asyncdispatch, strformat, uri]

import pkg/[httpx, chronicles]

proc pathAndQuery(uri: sink Uri): string =
  ## Returns the path and query combined
  if uri.query != "":
    return uri.path & "?" & uri.query
  uri.path

proc addLogging*(app: var App) =
  ## Enables logging with the app.
  ## All handlers passed will be registered on every spawned thread
  # TODO: Use proper logfmt
  app.beforeEach do (ctx: Context) {.async.}:
    debug "Starting request", meth=ctx.httpMethod, path = $ctx.url

  app.afterEach do (ctx: Context, err: ref Exception) {.async.}:
    if err != nil:
      error "Request failed", staus=ctx.response.code, error = $err.name, msg=err.msg, trace=err.getStackTrace()
    else:
      info "Request finished", meth=ctx.httpMethod, code=ctx.response.code, path = $ctx.url
