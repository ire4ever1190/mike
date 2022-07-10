import httpx
import ../context
import ../common
import std/[
  strtabs,
  parseutils,
  options
]

import std/uri except decodeQuery

## This module implements code for parsing URL encoded form
##
##


type URLEncodedForm = StringTableRef

proc urlForm*(ctx: Context): UrlEncodedForm =
    ## Get the key values from the form body
    ## It is recommended to cache this result instead of calling it for each value.
    ## The form parameters are considered case insensitive
    runnableExamples:
      import mike

      "/form" -> get:
        let form = ctx.urlForm
        ctx.send form["name"]

      "/form" -> post: # Works for POST requests also
        let form = ctx.urlForm
        ctx.send form["name"]
    #==#
    if ctx.request.httpMethod.get() == HttpPost:
      let body = ctx.request.body.get()
      result = newStringTable(modeStyleInsensitive)
      for (key, value) in body.decodeQuery():
        result[key] = value
    else:
      result = ctx.queryParams
