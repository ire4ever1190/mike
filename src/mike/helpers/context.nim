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
  strformat,
  jsonutils
]
import json as j
import ../context
import ../response as res
import ../errors
import ../common
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

func allowsBody*(ctx: Context): bool {.inline.} =
  ## Returns true if the request allows a body to be sent
  ctx.httpMethod != HttpHead

proc send*(ctx: Context, body: sink string, code: HttpCode, extraHeaders: HttpHeaders = nil) =
    ## Responds to a context and overwrites the status code.
    ## If responding to a `HEAD` or `OPTIONS` request then the body isn't send (But the `Content-Length` is set)
    assert not ctx.handled, "Response has already been sent"
    ctx.response.code = code
    ctx.request.send(
        body = if ctx.allowsBody: body else: "",
        code = ctx.response.code,
        headers = (ctx.response.headers & extraHeaders).toString(),
        contentLength = some(body.len) # Pass seperately so HEAD requests still have length
    )
    ctx.handled = true

proc send*(ctx: Context, json: sink JsonNode, code = Http200, extraHeaders: HttpHeaders = nil) =
  ## Responds with JSON to the client. Automatically sets the **Content-Type** header to `"application/json"`
  ctx.response.headers["Content-Type"] = "application/json"
  ctx.send(
    body = $ json,
    code,
    extraHeaders = extraHeaders
  )


proc send*[T: object | ref object | array | seq | set](ctx: Context, obj: sink T,
                                                       code = Http200, extraHeaders: HttpHeaders = nil) {.inline.} =
  ## Responds to a context in json format with obj `T`.
  ## Automatically sets the **Content-Type** header to `"application/json"`
  ctx.send(obj.toJson(), code, extraHeaders)

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
  ## Responds with just a status code. Ignores the current response body
  ctx.send(
    "",
    code,
    extraHeaders = extraHeaders
  )

const
  maxReadAllBytes* {.intdefine.} = 10_000_000
    ## Max size in bytes before streaming the file to the client

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
  # Work around for bug in std/times
  {.cast(gcsafe).}:
    ctx.getHeader(header).parse(httpDateFormat, utc()) < zeroedDate

proc setContentType*(ctx: Context, fileName: string) =
  ## Sets the content type to be for **fileName** e.g. `"index.html"` will set `"Content-Type"` header to `"text/html"`
  let (_, _, ext) = fileName.splitFile()
  {.gcsafe.}: # Only reading from mimeDB so its safe
    ctx.setHeader("Content-Type", mimeDB.getMimetype(ext))

proc startStreaming*(ctx: Context, contentLength = none(int)) {.inline.} =
  ## Sends everything but the body to the client. Allows you to start
  ## streaming content to the client.
  ctx.response.body.setLen(0)
  ctx.request.respond(ctx, contentLength)
  ctx.handled = true

proc sendPartial*(ctx: Context, data: sink string) {.inline.} =
  ## Sends some data directly to the client. You must have called [startStreaming] or [send] first
  ## So that the client has recieved headers and status code.
  when not defined(release):
    assert ctx.handled, "You haven't started the response yet"
  ctx.request.unsafeSend(data)

proc startChunking*(ctx: Context) =
  ## Allows you to start sending [chunks](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Transfer-Encoding#chunked_encoding) back to the client.
  ## Use this if streaming a large response to the client
  ctx.setHeader("Transfer-Encoding", "chunked")
  ctx.startStreaming()

proc sendChunk*(ctx: Context, data: sink string) =
  ## Sends a chunk to the client. Send an empty chunk when are finished
  var payload = data.len.toHex()
  payload.removePrefix("0")
  payload &= "\r\n" & data & "\r\n"
  ctx.sendPartial(payload)

proc startSSE*(ctx: Context, retry = 3000) =
  ## Allows you to start sending [server sent events](https://en.wikipedia.org/wiki/Server-sent_events) to the client.
  ##
  ## * **retry**: How quickly in milliseconds the client should try and reconnect
  ctx.setHeader("Content-Type", "text/event-stream")
  ctx.setHeader("Cache-Control", "no-store")
  ctx.startChunking()
  ctx.sendChunk("retry: " & $retry & "\n\n")

proc stopSSE*(ctx: Context) =
  ## Tells the client that the events have stopped
  ctx.sendChunk("")

proc sendEvent*(ctx: Context, event, data: string) =
  ## Sends an event with associated data. **event** isn't sent if it's empty (Body is still sent though)
  var payload = ""
  if event != "":
    payload &= "event: " & event & '\n'
  for line in data.splitLines():
    payload &= "data: " & line & '\n'
  payload &= '\n'
  ctx.sendChunk(payload)

proc requestRange*(ctx: Context): tuple[start, finish: Option[int]] =
  ## Returns start and end positions for a [range request](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests).
  ## Range requests are still valid if either start or finish don't exist. But if both don't exist then the request is invalid.
  ## This currently only supports single range requests
  if ctx.hasHeader("Range"):
    let val = ctx.getHeader("Range")
    var i = val.skip("bytes=")
    if i == 0:
      return
    # If its missing the start range then we don't what the end to be parsed
    # as a negative number
    var intVal, intLength: int
    if val[i] != '-':
      intLength = val.parseInt(intVal, i)
      if intLength != 0:
        i += intLength
        result.start = some intVal
    if i >= val.len or val[i] != '-':
      return
    i += 1
    intLength = val.parseInt(intVal, i)
    if intLength != 0:
      result.finish = some intVal

proc closed*(ctx: Context): bool {.inline.} =
  ## Returns true if the client has disconnected from the server
  result = ctx.request.closed

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

    ctx.setHeader("Accept-Ranges", if allowRanges: "bytes" else: "none")

    ctx.setHeader("Last-Modified", info.lastWriteTime.inZone(utc()).format(httpDateFormat))
    ctx.setContentType(filePath)

    # We try to support range based request. But if we can't parse correctly (Like a multirange request)
    # we simply ignore and return 200
    if allowRanges and ctx.hasHeader("Range"):
      let (start, finish) = ctx.requestRange
      if start.isSome or finish.isSome:
        let file = openAsync(filePath, fmRead)
        defer: close file
        let
          fileSize = file.getFileSize().int
          startByte = start.get(fileSize - finish.get(0))
          finishByte = if start.isSome: finish.get(fileSize - 1) else: fileSize - 1
          size = (finishByte - startByte) + 1 # We have +1 here since it is inclusive of the first byte

        if finishByte > fileSize or size <= 0:
          raise newRangeNotSatisfiableError(fmt"Range is invalid (start: {startByte}, end: {finishByte}, fileSize: {fileSize})")
        file.setFilePos(startByte)

        ctx.status = Http206
        ctx.setHeader("Content-Range", fmt"bytes {startByte}-{finishByte}/{file.getFileSize()}")
        ctx.startStreaming(some size)
        if ctx.httpMethod == HttpHead:
          return
        # We already have the file open so might as well stream everything
        var read = 0
        while not ctx.closed and read < size:
          let readSize = min((size - read), bufsize)
          read += readSize
          ctx.sendPartial(await file.read(readSize))
        return
    # If not doing range request then check if we need to stream file or not.
    # We want to not stream for small files so that we can compress them.
    if info.size >= maxReadAllBytes:
      # NOTE: Don't know how to partially use zippy so we don't support compression
      # if streaming the file
      ctx.startStreaming(some info.size.int)
      # Start streaming the file
      if ctx.httpMethod == HttpHead:
        return
      let file = openAsync(filePath, fmRead)
      defer: close file
      while not ctx.closed:
        let buffer = await file.read(bufsize)
        if buffer == "": # Empty means end of file
          break
        ctx.sendPartial(buffer)
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
