import std/[
  mimetypes,
  os,
  httpcore,
  asyncdispatch,
  times,
  strutils,
  parseutils,
  options,
  asyncfile,
  strscans,
  strformat
]
import json as j
import ../context
import ../response as res
import ../errors
import request
import response
import httpx
import pkg/zippy


proc `%`(h: HttpCode): JsonNode {.used.} =
  result = newJInt(h.ord)

proc `&`(parent, child: HttpHeaders): HttpHeaders =
    ## Merges the child headers with the parent headers and returns them has a new header
    result = parent
    if child != nil:
        for k, v in child:
            result[k] = v


proc send*(ctx: Context, body: sink string, code: HttpCode, extraHeaders: HttpHeaders = nil) =
    ## Responds to a context and overwrites the status code.
    ## If responding to a `HEAD` or `OPTIONS` request then the body isn't send (But the `Content-Length` is set)
    assert not ctx.handled, "Response has already been sent"
    ctx.response.code = code
    ctx.request.send(
        body = if ctx.httpMethod notin {HttpHead, HttpOptions}: body else: "",
        code = ctx.response.code,
        headers = (ctx.response.headers & extraHeaders).toString(),
        contentLength = some (if ctx.httpMethod != HttpOptions: body.len else: 0)  # Why does HTTPX have it as a string?
    )
    ctx.handled = true

proc send*[T: object | ref object](ctx: Context, obj: sink T, code = Http200, extraHeaders: HttpHeaders = nil) =
    ## Responds to a context in json format with obj T
    ## automatically sets the `Content-Type` header to "application/json"
    ctx.response.headers["Content-Type"] = "application/json"
    ctx.send(
        body = $ %* obj,
        code,
        extraHeaders = extraHeaders
    )

proc send*(ctx: Context, prob: ProblemResponse, extraHeaders: HttpHeaders = nil) =
  ## Sends a problem response back. Automatically sets the response code to
  ## the one specifed in **prob**
  ctx.send(prob, prob.status, extraHeaders)

proc send*(ctx: Context, body: sink string, extraHeaders: HttpHeaders = nil) =
    ## Responds to a context with `body` and does not overwrite
    ## the current status code
    ctx.send(
        body,
        ctx.response.code,
        extraHeaders = extraHeaders
    )

proc send*(ctx: Context, code: HttpCode, extraHeaders: HttpHeaders = nil) =
  ## Responds with just a status code
  ctx.send(
    "",
    code,
    extraHeaders = extraHeaders
  )

const
  maxReadAllBytes {.intdefine.} = 10_000_000
    ## Max size in bytes before buffer reading
  lastModifiedFormat = initTimeFormat("ddd',' dd MMM yyyy HH:mm:ss 'GMT'")
  
let mimeDB = newMimeTypes()

const compressionString: array[CompressedDataFormat, string] = ["detect", "zlib", "gzip", "deflate"]

proc sendCompressed*(ctx: Context, body: sink string, compression: CompressedDataFormat,
                     code = Http200, extraHeaders: HttpHeaders = nil) =
  ## Sends **body** but compresses it with [compression](https://nimdocs.com/treeform/zippy/zippy/common.html#CompressedDataFormat).
  ## Currently only `dfGzip` and `dfDeflate` are supported. Compresses even if the client doesn't say they support the compression
  ctx.setHeader("Content-Encoding", compressionString[compression])
  ctx.send(body.compress(BestSpeed, compression), code, extraHeaders)

proc getCompression(acceptEncoding: string): string =
  ## Takes in an Accept-Encoding header and returns the first
  ## usable compression (usable means supported by zippy). This currently
  ## doesn't support * or qvalue ratings
  var i = 0
  while i < acceptEncoding.len:
    var compression: string
    i += acceptEncoding.parseUntil(compression, {',', ';'}, i)
    if compression in compressionString:
      return compression
    i += acceptEncoding.skipUntil(' ', i) + 1

proc supportedCompression*(ctx: Context): Option[CompressedDataFormat] =
  ## Returns the compression that is supported by the context.
  ## If it doesn't support any compression then `none` is returned
  case getCompression(ctx.getHeader("Accept-Encoding", ""))
  of "gzip":
    some dfGzip
  of "deflate":
    some dfDeflate
  else:
    none CompressedDataFormat

proc sendCompressed*(ctx: Context, body: sink string, code = Http200, extraHeaders: HttpHeaders = nil) =
  ## Sends **body** and trys to compress it. Checks `Accept-Encoding` header to see what
  ## it can compress with. Doesn't compress if nothing in `Accept-Encoding` is implemented or the header is missing
  let compression = ctx.supportedCompression
  if compression.isSome():
    ctx.sendCompressed(body, compression.get(), code, extraHeaders)
  else:
    ctx.send(body, code, extraHeaders)

proc beenModified*(ctx: Context, modDate: DateTime = now()): bool =
  ## Returns `true` if **modDate** is newer than `If-Modified-Since` in the request.
  const header = "If-Modified-Since"
  # We want to remove nano seconds so that the comparison
  # doesn't take them into account
  let zeroedDate = dateTime(
    modDate.year,
    modDate.month,
    modDate.monthDay,
    modDate.hour,
    modDate.minute,
    modDate.second,
    zone = utc(),
  )
  if not ctx.hasHeader(header):
    # If the request doesn't have If-Modifie-Since
    # then we can assume our files are always newer
    return true

  ctx.getHeader(header).parse(lastModifiedFormat, utc()) < zeroedDate

proc setContentType*(ctx: Context, fileName: string) =
  ## Sets the content type to be for **fileName** e.g. `"index.html"` will set `"Content-Type"` header to `"text/html"`
  let (_, _, ext) = fileName.splitFile()
  {.gcsafe.}: # Only reading from mimeDB so its safe
    ctx.setHeader("Content-Type", mimeDB.getMimetype(ext))

proc sendFile*(ctx: Context, filename: string, dir = ".", headers: HttpHeaders = nil,
               downloadName = "", charset = "utf-8", bufsize = 4096, allowRanges = false) {.async.} =
    ## Responds to a context with a file.
    ##
    ## * **allowRanges**: Whether to support [range requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Only use
    ##                  this if there is little processing before sending the file
    # Implementation was based on staticFileResponse in https://github.com/planety/prologue/blob/devel/src/prologue/core/context.nim
    let filePath = dir / filename
    if not filePath.fileExists:
        raise newNotFoundError(filename & " cannot be found")

    # Check user can read the file and user isn't trying to escape to another folder'
    if fpUserRead notin filePath.getFilePermissions() or not filePath.isRelativeTo(dir):
        raise newForbiddenError("You are unauthorised to access this file")

    if downloadName != "":
      ctx.setHeader("Content-Disposition", "inline;filename=" & filename)

    let info = getFileInfo(filePath)
    if not ctx.beenModified(info.lastWriteTime.utc()):
      # Return 304 if the file hasn't been modified since the client says they last got it
      ctx.send("", Http304)
      return
    if allowRanges:
      ctx.setHeader("Accept-Ranges", "bytes")

    ctx.setHeader("Last-Modified", info.lastWriteTime.inZone(utc()).format(lastModifiedFormat))
    ctx.setContentType(filePath)

    if allowRanges and ctx.hasHeader("Range"):
      let (ok, start, finish) = ctx.getHeader("Range").scanTuple("bytes=$i-$i")
      if not ok or finish < start:
        raise newBadRequestError("Range header is not valid")
      let file = openAsync(filePath, fmRead)
      defer: close file
      file.setFilePos(start)

      ctx.status = Http206
      ctx.setHeader("Content-Range", fmt"bytes {start}-{finish}/{file.getFileSize()}")
      # We have +1 here since it is inclusive of the first byte
      ctx.send(await file.read((finish - start) + 1))
    else:
      if info.size >= maxReadAllBytes:
        # NOTE: Don't know how to partially use zippy so we don't support compression
        # if streaming the file
        ctx.response.body.setLen(0)
        ctx.request.respond(ctx, some info.size.int)
        # Start streaming the file
        if ctx.httpMethod != HttpHead:
          let file = openAsync(filePath, fmRead)
          defer: close file
          while true:
            let buffer = await file.read(bufsize)
            if buffer == "": # Empty means end of file
              break
            ctx.request.unsafeSend(buffer)
      else:
        let compression = ctx.supportedCompression
        if compression.isSome():
          ctx.sendCompressed(filePath.readFile(), compression.get())
        elif ctx.httpMethod == HttpHead:
          # They don't support compression. But we can still send the filesize
          # without needing to open the file
          ctx.request.respond(ctx, some info.size.int)
        else:
          ctx.send(filePath.readFile())
    ctx.handled = true
