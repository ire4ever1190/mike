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
import common
import times

import std/genasts
import std/macros

import errors

##[
  This module provides the [servePublic] macro that enables you to serve all files inside a folder. You can also compile
  your application with `-d:mikeStaticFiles` or pass `staticFiles = true` to [servePublic] to make all the files be included
  in your binary so you don't need to deploy the files seperatly from the binary
]##

let compiledAt = parse(CompileDate & " " & CompileTime, "yyyy-MM-dd HH:mm:ss")

    
macro servePublic*(folder, path: static[string], renames: openarray[(string, string)] = [],
                   staticFiles: static[bool] = defined(mikeStaticFiles)) =
  ## Serves files requested from **path**.
  ## If **staticFiles** is true or the file is compiled with `-d:mikeStaticFiles`
  runnableExamples "-r:off":
    import mike
    servePublic("public/", "/static")
    # Files inside public folder are now accessible at static/
    # e.g. index.html inside public/ will be at url http://localhost/static/index.html

    # You can also rename files so they can be accepted at a different path
    servePublic("/", "/static", renames = {
      "": "index.html" # / will return /static/index.html (If no other handler handles it)
    })
  #==#
  # This is done as a macro so that we can implement loading
  # files at comp time for a static binary (In terms of public files)
  if staticFiles:
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

    fullPath -> [get, head]:
      let origPath = ctx.pathParams["file"]
      {.gcsafe.}:
        let path = if origPath in renameTable: renameTable[origPath]
                   else: origPath
      when not staticFiles:
        await ctx.sendFile(
          path,
          folder,
          allowRanges = true
        )
      else:
        {.gcsafe.}:
          if path in files:
            if not ctx.beenModified(compiledAt):
              ctx.send("", Http304)
            else:
              ctx.setHeader("Last-Modified", compiledAt.format(httpDateFormat))
              ctx.setContentType(path)
              ctx.sendCompressed(files[path])
          else:
            raise newNotFoundError(path & " not found")

