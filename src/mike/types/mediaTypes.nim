## Module for interacting with [media types](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/MIME_types) in a simple manner

import pkg/nort
import pkg/nort/helpers

import std/tables

let grammar = block:
  let
    paramValue = (not e({'=', ';'}) * dot())
    # Simple `key=value`
    param = paramValue$key * -e('=') * paramValue$value
    parameters = *(-e';' * ws * param * ws)
    family = dot.until(e'/')
    subtype = dot().until(';')
  family$kind * e('/') * subtype$subkind * parameters$parameters

type
  MediaType* = object
    ## This stores a media type e.g. `application/json`
    family*: string ## Family of the type e.g. application
    subtype*: string ## Subtype within the family e.g. json
    params*: Table[string, string] ## Parameters for the type

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
    assert json.params["boundary"] == "boundaryString"
