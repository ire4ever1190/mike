import tables
import macros
import strformat
from router import checkPathCharacters

proc expectKind*(n: NimNode, k: NimNodeKind, msg: string) =
    if n.kind != k:
        error(msg, n)

proc getPath*(handler: NimNode): string =
    ## Gets the path from a DSL adding call
    ## Errors if the node is not a string literal or if it has
    ## illegal characters in it (check router.nim for illegal characters)
    # handler can either be a single strLitNode or an nnkCall with the path
    # as the first node
    let pathNode = if handler.kind == nnkStrLit: handler else: handler[0]
    pathNode.expectKind(nnkStrLit, "The path is not a string literal")
    result = pathNode.strVal
    let (resonable, character) = result.checkPathCharacters()
    if not resonable:
        fmt"Path has illegal character {character}".error(pathNode)

proc toAsyncHandler*(path: string, handler: NimNode): NimNode =
    ## Converts a untyped handler to it's `AsyncHandler` form.
    ## This accepts the untyped body from two types of calls
    ##
    ## ..code-block:: nim
    ##
    ##  get "/path" do:
    ##      # body
    ##  get "/path":
    ##      # body
    ##  get "/path" do (ctx: Context, futureImp: string):
    ##      # body
    ##
    ## Does the following AST transforms
    ##  - Adding the Future[string] return type
    ##  - Converting it to a proc
    # TODO: Add parameter handling like in dimscmd
    # e.g. do (body: Body[json[Person])
    # parameters should match to url parameters automatically
    discard