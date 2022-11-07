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
# import helpers/context
import strtabs

import times

import std/genasts
import std/macros

import errors


    
macro servePublic*(folder, path: static[string], renames: openarray[(string, string)] = @[],
                   staticFiles = defined(mikeStaticFiles)) =
  ## Serves files requested from **path**.
  ## If **staticFiles** is true or the file is compiled with `-d:mikeStaticFiles`
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
  result = genAst(fullPath, folder, renames, staticFiles):
    let renameTable = newStringTable(renames)

    # Build table of files if needed
    when staticFiles:
      # Might crit bit tree be better?
      let files = static:
        var files = newStringTable()
        for file in walkDirRec(folder, relative = true):
          files[file] = (folder / file).readFile()
        files
      # Sadly I can't get time at compile time, so I just
      # get the time when run and use that for caching
      let startTime = now()

    fullPath -> get:
      let origPath = ctx.pathParams["file"]
      {.gcsafe.}:
        let path = if origPath in renameTable: renameTable[origPath]
                   else: origPath
      when not staticFiles:
        await ctx.sendFile(
          path,
          folder
        )
      else:
        {.gcsafe.}:
          if path in files:
            ctx.send(files[path])
          else:
            raise NotFoundError(path & " not found")

