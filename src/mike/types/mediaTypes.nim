## Module for interacting with [media types](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/MIME_types) in a simple manner

import pkg/nort
import pkg/nort/helpers
import pkg/casserole

import std/tables
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


proc initMediaType*(inp: string): MediaType =
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

  if Some(res) ?== grammar.match(inp):
    return res
  raise (ref InvalidMediaType)(msg: "Failed to parse media type from: " & inp)
