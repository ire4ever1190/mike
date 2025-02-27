import ./[router, context, common]
import std/[httpcore, macros]

## This is a fully typesafe version of the API. All responses should be
## done by returning like a normal function. For getting data, [Context]
## can be used by using context hooks is strongly encouraged

# TODO Support future returns, better extraction like `createASyncHandler`
# TODO Support implicit path parameters

type
  Handler* = AsyncHandler
  App* = object
    ## Entrypoint for a Mike application.
    ## All routes get registered to this
    router: Router[AsyncHandler]
      ## Routes requests to their handlers

using mapp: var App

proc initApp(): App =
  ## Creates a new Mike app.
  return App()

proc internalMap(mapp; verbs: set[HttpMethod], path: string, position: HandlerPos, handler: Handler) =
  ## Internal function for mapping a handler into the [App]. This is called after a handler
  ## has been transformed via our [placeholdermacro]
  mapp.router.map(verbs, path, handler, position)

macro wrapProc(x: proc): AsyncHandler =
  ## Wraps a proc in context hooks to generate the parameters
  let impl = x.getTypeImpl()
  let
    body = newStmtList()
    innerCall = newCall(x)
    ctxIdent = ident"ctx"

  # Build body from params
  for identDef in impl.params[1 .. ^1]:
    for param in identDef[0 ..< ^2]:
      let ident = ident $param
      innerCall &= newCall(nnkDotExpr.newTree(param, ident"H"), ctxIdent, newLit $param)

  # Build a proc that just calls all the hooks and then calls the original proc
  result = newProc(
    params=[parseExpr"Future[string]", newIdentDefs(ctxIdent, ident"Context")],
    pragmas = nnkPragma.newTree(ident"async"),
    body = newStmtList(innerCall)
  )
  echo result.toStrLit

proc map[P: proc](mapp; verbs: set[HttpMethod], path: string, position: HandlerPos, handler: P) =
  ## Low level function for adding a handler into the router. Handler gets transformed
  ## According to parameters/return
  mapp.internalMap(verbs, path, position, wrapProc(handler))

# proc map(mapp; verbs: set[HttpMethod], path: string, handler: proc) =
  # Maps a function to a set of verbs.
  # createHandler(handler)

var app = App()

import ./[ctxhooks, helpers]
import asyncdispatch


app.map({HttpGet}, "/test", Middle) do (x: Cookie[int]) -> string:
  echo x


when false:
  app.map({HttpGet}, "/") do (y: Header[string]) -> string:
    return y



