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

import ./app

import std/genasts
import std/macros
import std/private/globs

import errors

##[
  This module provides the [servePublic] macro that enables you to serve all files inside a folder. You can also compile
  your application with `-d:mikeStaticFiles` or pass `staticFiles = true` to [servePublic] to make all the files be included
  in your binary so you don't need to deploy the files seperatly from the binary
]##

let compiledAt = parse(CompileDate & " " & CompileTime, "yyyy-MM-dd HH:mm:ss")

proc servePublic*(app: var App, folder, path: static[string], renames: openarray[(string, string)] = [],
                  staticFiles: static[bool] = defined(mikeStaticFiles)) =
  ## Serves files requested from **path** that exist in **folder**.
  ## If **staticFiles** is true or the file is compiled with `-d:mikeStaticFiles`
  runnableExamples "-r:off":
    import mike

    let app = initApp()

    app.servePublic("public/", "/static")
    # Files inside public folder are now accessible at static/
    # e.g. index.html inside public/ will be at url http://localhost/static/index.html

    # You can also rename files so they can be accepted at a different path
    app.servePublic("/", "/static", renames = {
      "": "index.html" # / will return /static/index.html (If no other handler handles it)
    })
  #==#
  const fullPath = $(path.parseUri() / "^file")

  let
    # This is a strange hack to get around a codegen bug where the
    # array isn't initialised
    # TODO: Somehow minify the case and report the bug
    renameList = if renames.len > 0: @renames else: @[]
    renameTable = newStringTable(renameList)

  when not staticFiles:
    # The normal runtime implementation is simple, just return the path
    # and let sendFile take care of the dirExists
    app.map({HttpGet, HttpHead}, fullPath) do (ctx: Context, file: string) {.async.}:
      await context.sendFile(ctx,
        renameTable.getOrDefault(file, file),
        folder,
        allowRanges = true
      )
  else:
    # Static files are a little more complex. We need to build a table
    # of the files so we can look them up later
    let files = static:
      var files = newStringTable()
      for file in walkDirRec(folder, relative = true):
        let unixPath = nativeToUnixPath(file)
        files[unixPath] = (folder / file).readFile()
      files

    app.map({HttpGet, HttpHead}, fullPath) do (ctx: Context, file: string):
      let path = renameTable.getOrDefault(file, file)
      if path notin files:
        raise newNotFoundError(path & " not found")

      if not context.beenModified(ctx, compiledAt):
        ctx.send("", Http304)
      else:
        ctx.setHeader("Last-Modified", compiledAt.format(httpDateFormat))
        context.setContentType(ctx, path)
        ctx.sendCompressed(files[path])

proc servePublic*(folder, path: static[string], renames: openarray[(string, string)] = [],
                   staticFiles: static[bool] = defined(mikeStaticFiles)) {.deprecated.} =
  ## Verison of [servePublic] that works with the old DSL
  http.servePublic(folder, path, renames, staticFiles)
