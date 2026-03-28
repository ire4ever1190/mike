## Module for interacting with [media types](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/MIME_types) in a simple manner

import pkg/nort
import pkg/nort/helpers
import pkg/casserole

import std/[tables, strformat]
export tables


type
  MediaType* = object
    ## This stores a media type e.g. `application/json`
    family*: string ## Family of the type e.g. application
    subtype*: string ## Subtype within the family e.g. json
    params*: Table[string, string] ## Parameters for the type
  InvalidMediaType* = object of ValueError
    ## Raised when trying to parse an invalid media type

let grammar = block:
  let
    paramValue = +(not e({'=', ';'}) * dot())
    # Simple `key=value`
    param = paramValue$key * -e('=') * paramValue$value
    parameters = *(-e(';') * ?ws * param * ?ws)
    family = dot().until(e'/')
    subtype = dot().until(e';')
  #kind/subkind; key=value
  let gram = family$kind * e('/') * subtype$subkind * parameters$parameters

  # Map it into a better type
  gram.map() do (inp: tuple[kind, subkind: string, parameters: seq[(string, string)]]) -> MediaType:
    MediaType(family: inp.kind, subtype: inp.subkind, params: inp.parameters.toTable())


func initMediaType*(inp: string): MediaType =
  ## Parses a media type from an input string
  runnableExamples:
    # Basic types can be parsed
    let json = initMediaType("application/json")
    assert json.family == "application"
    assert json.subtype == "json"
  runnableExamples:
    # Parameters are supported
    let multipart = initMediaType("multipart/form-data; boundary=boundaryString")
    assert multipart.params["boundary"] == "boundaryString"
  {.cast(noSideEffect).}:
    if Some(res) ?== grammar.match(inp):
      return res
  raise (ref InvalidMediaType)(msg: "Failed to parse media type from: " & inp)

proc `~=`*(left, right: MediaType): bool =
  ## Checks if the `left` media type is equivilant to the `right`.
  ## Equivilance means that `family` and `subtype` match exactly or one of the values is `*`
  runnableExamples:
    # Matches exactly
    assert initMediaType("application/json") ~= initMediaType("application/json")
    # Matches pattern
    assert initMediaType("application/*") ~= initMediaType("application/json")
    assert initMediaType("application/json") ~= initMediaType("application/*")

  template eq(a, b: string): bool =
    ## Checks if either both are same value or one is `*`
    a == b or a == "*" or b == "*"
  return eq(left.family, right.family) and eq(left.subtype, right.subtype)

func `<=`*(left, right: MediaType): bool =
  ## Checks that `left` is either a subtype or equal to `right`.
  ## Unlike [~=], this is not commutative since `foo` is a subtype of `*` but `*` is not a subtype of `foo`
  runnableExamples:
    # Matches exactly
    assert initMediaType("application/json") <= initMediaType("application/json")
    # Matches pattern
    assert initMediaType("application/json") <= initMediaType("application/*")
    # We are expecting json, we don't accept anything
    assert not (initMediaType("application/*") <= initMediaType("application/json"))

  template eq(a, b: string): bool =
    ## Checks if either both are same value or one is `*`
    a == b or b == "*"
  return eq(left.family, right.family) and eq(left.subtype, right.subtype)

func `$`*(mediaType: MediaType): string =
  ## Formats mediatype into string representation
  runnableExamples:
    let mediaType = MediaType(
      family: "application",
      subtype: "json",
      params: {"foo": "bar"}.toTable()
    )
    assert $mediaType == "application/json; foo=bar"
  result = fmt"{mediaType.family}/{mediaType.subtype}"
  for key, value in mediaType.params:
    result &= fmt"; {key}={value}"
