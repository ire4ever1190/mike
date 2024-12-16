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

proc map(mapp; verbs: set[HttpMethod], path: string, position: HandlerPos, handler: proc) =
  ## Low level function for adding a handler into the router. Handler gets transformed
  ## According to parameters/return

# proc map(mapp; verbs: set[HttpMethod], path: string, handler: proc) =
  # Maps a function to a set of verbs.
  # createHandler(handler)

var app = App()

import ./[ctxhooks, helpers]
import asyncdispatch

macro handler*(prc: untyped): untyped =
  ## Pragma that marks a proc as a handler.
  ## This is only needed if declaring a standalone proc that has
  ## context hooks
  # This handles converting the types in the proc handler into
  # that types that the context hooks returns
  # Small sanity check
  if prc.kind notin {nnkProcDef, nnkFuncDef}:
    "Handler must be a procedure declaration".error(prc)
  # Context variable passed in from the router
  let ctxSym = genSym(nskParam, "ctx")
  # Extract the procedures parameters and create a series of variables that
  # will get passed directly. We make them vars so that var parameters can
  # be used.
  var hookCalls: seq[(string, NimNode)]
  for identDef in prc[3][1..^1]:
    for param in identDef[0 ..< ^2]:
      let name = $param
      hookCalls &= (
        name,
        newCall(ident"fromRequest", ctxSym, newLit name, nnkBracketExpr.newTree(ident"typedesc", identDef[^2]))
      )
  # Create the var section containing them.
  # Make it a var section in case the parameter requires mutability (Should we allow mutable parameters?)
  # Also construct the call to the original handler
  var hookCallVars = nnkVarSection.newTree()
  var handlerCall = newCall(prc)
  for (name, call) in hookCalls:
    let varIdent = ident name
    hookCallVars &= nnkIdentDefs.newTree(varIdent, newEmptyNode(), call)
    handlerCall &= varIdent
  # Send the response
  let respCall = newCall("sendResponse", ctxSym, handlerCall)
  # Now generate the new proc
  result = quote do:
    proc handler(`ctxSym`: Context) {.async.} =
      `hookCallVars`
      `respCall`
  echo result.toStrLit

proc test(y: Header[string]): string {.handler.} = y

when false:
  app.map({HttpGet}, "/") do (y: Header[string]) -> string:
    return y



