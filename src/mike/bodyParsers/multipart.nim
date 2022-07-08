import std/[
  strtabs,
  parseutils,
  strutils,
  options,
  tables
]

import ../context
import ../helpers
import httpx

##
## Contains implementation and helpers for getting multipart form data from a context
##


type
  MultipartValue* = object
    name*, value*: string
    params*: StringTableRef

# Have some type safe getters for certain parameters

func filename*(mv: MultipartValue): Option[string] =
  ## Returns the name of the file uploaded in the part if it exists
  if "filename" in mv.params:
    result = some mv.params["filename"]

func contentType*(mv: MultipartValue): Option[string] =
  ## Returns the content type of the part if it exists
  if "Content-Type" in mv.params:
    result = some mv.params["Content-Type"]

type State = enum
  Sep
  Head
  Body

func multipartForm*(ctx: Context): Table[string, MultipartValue] =
  ## Get multipart form data from context.
  ##
  ## .. Warning:: This loads the entire form into memory so be careful with large files
  let 
    contentHeader = ctx.getHeader("Content-Type")
    boundary = "\c\L--" & contentHeader[contentHeader.rfind("boundary=") + 9 .. ^1]
    body = ctx.request.body.get()

  var 
    i = 0
    state = Sep
    currVal = MultipartValue(params: newStringTable())
  
  while i < body.len:
    var line: string
    case state
    of Sep:
      i += body.parseUntil(line, "\c\L", i) + 2
      # Add the current value to the result if needed
      # then just start parsing head
      if currVal.name != "":
        result[currVal.name] = currVal
        currVal = MultipartValue(params: newStringTable())
      state = Head
    of Head:
      i += body.parseUntil(line, "\c\L", i) + 2
      if line == "" and body[i - 4] == '\c' and body[i - 3] == '\L':
        state = Body
      else:
        var 
          key: string
          lineI = line.parseUntil(key, ':') 
        if key == "Content-Disposition":
          # Parse the Content-Dispotition which has some special values
          # We don't care about the disposition type so we just skip to the params
          var value: string
          while lineI < line.len:
            value.setLen 0
            key.setLen 0
            # Skip past unneeded stuff
            lineI += line.skipUntil(';', lineI)
            lineI += line.skipWhile({';', ' '}, lineI)
            # Get key
            lineI += line.parseUntil(key, '=', lineI) + 1
            # Accoring to the RFC, short values that aren't special don't need to be
            # quoted so the quotes might be optional
            if line[lineI] == '"': 
              inc lineI
            lineI += line.parseUntil(value, {'"', ';'}, lineI) + 1
            # Name is special
            if key == "name":
              currVal.name = value
            else:
              currVal.params[key] = value
        else:
          lineI += line.skipWhile({':', ' '}, lineI)
          currVal.params[key] = line[lineI .. ^1] 
    of Body:
      i += body.parseUntil(currVal.value, boundary, i) + 2
      state = Sep
  if currVal.name != "":
    result[currVal.name] = currVal

export tables
