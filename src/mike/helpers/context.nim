import std/[
  mimetypes,
  os,
  httpcore,
  json,
  asyncdispatch,
  times,
  strutils,
  parseutils,
  options,
  asyncfile
]
import ../context
import ../response as res
import ../errors
import request
import response
import httpx
import pkg/zippy

##
## Helpers for working with the context
##

proc `%`(h: HttpCode): JsonNode {.used.} =
  result = newJInt(h.ord)

proc `&`(parent, child: HttpHeaders): HttpHeaders =
    ## Merges the child headers with the parent headers and returns them has a new header
    result = parent
    if child != nil:
        for k, v in child:
            result[k] = v


proc send*(ctx: Context, body: sink string, code: HttpCode, extraHeaders: HttpHeaders = nil) =
    ## Responds to a context and overwrites the status code
    assert not ctx.handled, "Respons has already been sent"
    ctx.response.code = code
    ctx.response.body = body
    ctx.request.send(
        body = ctx.response.body,
        code = ctx.response.code,
        headers = (ctx.response.headers & extraHeaders).toString()
    )
    ctx.handled = true

proc send*[T](ctx: Context, obj: sink T, code = Http200, extraHeaders: HttpHeaders = nil) =
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

const
  maxReadAllBytes {.intdefine.} = 10_000_000
    ## Max size in bytes before buffer reading
  lastModifiedFormat = initTimeFormat("ddd',' dd MMM yyyy HH:mm:ss 'GMT'")
  
let mimeDB = newMimeTypes()

const compressionString: array[CompressedDataFormat, string] = ["detect", "zlib", "gzip", "deflate"]

proc sendCompressed*(ctx: Context, body: sink string, compression: CompressedDataFormat,
                     code = Http200, extraHeaders: HttpHeaders = nil) =
  ## Sends **body** but compresses it with `compression`.
  ## Currently only gzip and deflate are supported
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

proc sendCompressed*(ctx: Context, body: sink string, code = Http200, extraHeaders: HttpHeaders = nil) =
  ## Sends **body** and trys to compress it. Checks `Accept-Encoding` header to see what
  ## it can compress with. Doesn't compress if nothing in `Accept-Encoding` is implemented or the header is missing
  case getCompression(ctx.getHeader("Accept-Encoding", ""))
  of "gzip":
    ctx.sendCompressed(body, dfGzip, code, extraHeaders)
  of "deflate":
    ctx.sendCompressed(body, dfDeflate, code, extraHeaders)
  else:
    ctx.send(body, code, extraHeaders)

proc beenModified*(ctx: Context, modDate: DateTime): bool =
  ## Returns `true` if **modDate** is newer than `If-Modified-Since` in the request.
  const header = "If-Modified-Since"
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
  ## Sets the content type to be for **fileName**
  let (_, _, ext) = fileName.splitFile()
  {.gcsafe.}: # Only reading from mimeDB so its safe
    ctx.setHeader("Content-Type", mimeDB.getMimetype(ext))

proc sendFile*(ctx: Context, filename: string, dir = ".", headers: HttpHeaders = nil,
               downloadName = "", charset = "utf-8", bufsize = 4096) {.async.} =
    ## Responds to a context with a file
    # Implementation was based on staticFileResponse in https://github.com/planety/prologue/blob/devel/src/prologue/core/context.nim
    let filePath = dir / filename
    if not filePath.fileExists:
        raise NotFoundError(filename & " cannot be found")

    # Check user can read the file and user isn't trying to escape to another folder'
    if fpUserRead notin filePath.getFilePermissions() or not filePath.isRelativeTo(dir):
        raise ForbiddenError("You are unauthorised to access this file")

    if downloadName != "":
      ctx.setHeader("Content-Disposition", "inline;filename=" & filename)

    let info = getFileInfo(filePath)
    if not ctx.beenModified(info.lastWriteTime.utc()):
      # Return 304 if the file hasn't been modified since the client says they last got it
      ctx.send("", Http304)
      return

    ctx.setHeader("Last-Modified", info.lastWriteTime.inZone(utc()).format(lastModifiedFormat))
    ctx.setContentType(filePath)

    if info.size >= maxReadAllBytes and true:
      # NOTE: Don't know how to partially use zippy so we don't support compression
      # if streaming the file
      ctx.response.body.setLen(0)
      ctx.request.respond(ctx, some $info.size)
      # Start streaming the file
      let file = openAsync(filePath, fmRead)
      while true:
        let buffer = await file.read(bufsize)
        if buffer == "": # Empty means end of file
          break
        ctx.request.unsafeSend(buffer)
      close file
    else:
      # Check if the client allows us to compress the file
      ctx.sendCompressed filePath.readFile()

    ctx.handled = true
