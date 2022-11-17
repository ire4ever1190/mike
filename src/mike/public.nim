import dsl
import httpcore
import asyncdispatch
import strtabs
import httpx
import nativesockets
import uri
import os
import strformat
import helpers/context {.all.} except send, sendCompressed

import times

import std/genasts
import std/macros

import errors

##[
  This module provides the [servePublic] macro that enables you to serve all files inside a folder. You can also compile
  your application with `-d:mikeStaticFiles` or pass `staticFiles = true` to [servePublic] to make all the files be included
  in your binary so you don't need to deploy the files seperatly from the binary
]##

    
macro servePublic*(folder, path: static[string], renames: openarray[(string, string)] = [],
                   staticFiles = defined(mikeStaticFiles)) =
  ## Serves files requested from **path**.
  ## If **staticFiles** is true or the file is compiled with `-d:mikeStaticFiles`
  ## ```nim
  ## createDir("/static") # Folder needs to exist at compile time
  ## servePublic("public/", "/static")
  ## # Files inside public folder are now accessible at static/
  ## # e.g. index.html inside public/ will be at url http://localhost/static/index.html
  ## servePublic("/", "/static", renames = {
  ## "": "index.html" # / will return /static/index.html (If no other handler handles it)
  ## })
  ## ```
  #==#
  # This is done as a macro so that we can implement loading
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
      let startTime = now().utc

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
            if not ctx.beenModified(startTime):
              ctx.send("", Http304)
            else:
              ctx.setHeader("Last-Modified", startTime.format(lastModifiedFormat))
              ctx.setContentType(path)
              ctx.sendCompressed(files[path])
          else:
            raise newNotFoundError(path & " not found")

