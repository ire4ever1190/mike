import ./[router, context, common]
import std/[httpcore, macros]

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

macro createHandler(x: proc): untyped =
  ## Takes in a raw proc and performs the following rewrites
  ## - For each parameter, add context hook calls.
  ## - Wrap the procedure in another proc for type elision (Make it inline to remove this overhead).
  ## - In the wrapper, call the original procedure and call `toResponse` to send the values.
  # Get the type, since this returns a nnkProcTy it gets rid of having to
  # deal with different proc representations
  let typ = x.getTypeInst()
  # Small sanity check
  if typ.kind != nnkProcTy:
    "Handler must be a procedure/function".error(x)
  # Context variable passed in from the router
  let ctxSym = genSym(nskParam, "ctx")
  # Extract the procedures parameters and create a series of variables that
  # will get passed directly. We make them vars so that var parameters can
  # be used.
  var hookCalls: seq[(string, NimNode)]
  for identDef in typ[0][1..^1]:
    for param in identDef[0 ..< ^2]:
      let name = $param
      hookCalls &= (name, newCall(ident"fromRequest", ctxSym, newLit name, identDef[^2]))
  # Create the var section containing them.
  # Also construct the call to the original handler
  var hookCallVars = nnkVarSection.newTree()
  var handlerCall = newCall(x)
  for (name, call) in hookCalls:
    let varIdent = ident name
    hookCallVars &= nnkIdentDefs.newTree(varIdent, newEmptyNode(), call)
    handlerCall &= varIdent
  # Send the response
  let respCall = newCall("sendResponse", ctxSym, handlerCall)
  # Now generate the new proc
  return quote do:
    proc handler(`ctxSym`: Context) {.async.} =
      `hookCallVars`
      `respCall`




proc internalMap(mapp; verbs: set[HttpMethod], path: string, position: HandlerPos, handler: Handler) =
  ## Internal function for mapping a handler into the [App]. This is called after a handler
  ## has been transformed via our [placeholdermacro]
  mapp.router.map(verbs, path, handler, position)

proc map(mapp; verbs: set[HttpMethod], path: string, position: HandlerPos, handler: proc) =
  ## Low level function for adding a handler into the router. Handler gets transformed
  ## According to parameters/return

proc map(mapp; verbs: set[HttpMethod], path: string, handler: proc) =
  ## Maps a function to a set of verbs.
  createHandler(handler)

var app = App()

app.map({HttpGet}, "/") do (y: int) -> string:
  return ""



