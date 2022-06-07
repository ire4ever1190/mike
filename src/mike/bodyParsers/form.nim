import httpx
import ../context
import std/[
  strtabs,
  parseutils,
  options,
  uri
]

## This module implements code for parsing URL encoded form
##
##


type
    URLEncodedForm = StringTableRef

proc urlForm*(ctx: Context): UrlEncodedForm =
    ## Get the key values from the form body
    ## It is recommended to cache this result instead of calling it for each value.
    ## The form parameters are considered case insensitive
    runnableExamples:
      "/form" -> get:
        let form = ctx.urlForm
        ctx.send form["name"]

      "/form" -> post: # Works for POST requests also
        let form = ctx.urlForm
        ctx.send form["name"]
        
    if ctx.request.httpMethod.get() == HttpPost:
      let body = ctx.request.body.get()
      var index = 0
      result = newStringTable(modeStyleInsensitive)
      while index < body.len():
        var key, value: string
        index += body.parseUntil(key, until = '=', start = index) + 1 # skip =
        index += body.parseUntil(value, until = '&', start = index) + 1 # skip &
        result[key.decodeUrl()] = value.decodeUrl()
    else:
      result = ctx.queryParams
