import dsl
import context
import httpcore
import asyncdispatch
import strtabs
import httpx
import nativesockets
import uri
import os
import strformat
import helpers/context
import strtabs

import std/genasts
import std/macros
    
macro servePublic*(folder, path: static[string], renames: openarray[(string, string)] = @[]) =
  ## Serves files requested from **path**
  runnableExamples:
    setPublic("public/", "/static")
    # Files inside public folder are now accessible at static/
    # e.g. index.html inside public/ will be at url http://localhost/static/index.html
  runnableExamples:
    setPublic("/", "/static", renames = {
      "": "index.html" # / will return /static/index.html (If no other handler handles it)
    })
  #==#
  # This is done as a macro sso that we can implement loading
  # files at comp time for a static binary (In terms of public files)
  assert folder.dirExists, fmt"{folder} could not be found"
  let fullPath = $(path.parseUri() / "^file")

  # Now for the file sending code
  result = genAst(fullPath, folder, renames):
    let renameTable = newStringTable(renames)
    fullPath -> get:
      let origPath = ctx.pathParams["file"]
      {.gcsafe.}:
        let path = if origPath in renameTable: renameTable[origPath]
                   else: origPath

      await ctx.sendFile(
        path,
        folder
      )

