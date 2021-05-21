import httpx
import ../context
import std/strtabs
import std/parseutils
import std/options
## This module implements code for parsing URL encoded form
##
##


type
    URLEncodedForm = StringTableRef

proc parseForm*(ctx: Context): UrlEncodedForm =
    ## Get the key values from the form body
    if ctx.request.httpMethod.get() == HttpPost:
        let body = ctx.request.body.get()
        var index = 0
        result = newStringTable(modeStyleInsensitive)
        while index < body.len():
            var key, value: string
            index += body.parseUntil(key, until = '=', start = index) + 1 # skip =
            index += body.parseUntil(value, until = '&', start = index) + 1 # skip &
            result[key] = value
    else:
        result = ctx.queryParams
