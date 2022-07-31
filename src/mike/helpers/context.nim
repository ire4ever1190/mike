import std/[
  mimetypes,
  os,
  httpcore,
  json,
  asyncdispatch,
  times,
  strutils
]
import ../context
import ../response as res
import ../errors
import response
import request
import httpx
import pkg/zippy
##
## Helpers for working with the context
##

proc `%`(h: HttpCode): JsonNode =
  result = newJInt(h.ord)


proc `&`(parent, child: HttpHeaders): HttpHeaders =
    ## Merges the child headers with the parent headers and returns them has a new header
    result = parent
    if child != nil:
        for k, v in child:
            result[k] = v

proc send*(ctx: Context, body: sink string, code: HttpCode, extraHeaders: HttpHeaders = nil) =
    ## Responds to a context and overwrites the status code
    ctx.response.code = code
    ctx.response.headers["Content-Length"] = $body.len
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
  maxReadAllBytes {.strdefine.} = 10_000_000 # Max size in bytes before buffer reading
  lastModifiedFormat = "ddd',' dd MMM yyyy HH:mm:ss 'GMT'"
  
let mimeDB = newMimeTypes()

proc sendCompressed*(ctx: Context, body: sink string, 
                     code = Http200, extraHeaders: HttpHeaders = nil) =
  ## Sends **body** but compresses it with `gzip`
  ctx.setHeader("Content-Encoding", "gzip")
  ctx.send(body.compress(BestSpeed, dfGzip), code, extraHeaders)

proc zeroWriteTime(x: FileInfo): DateTime =
  ## Zeros the write time and returns it has a datetime (in UTC format)
  result = x.lastWriteTime.utc
  result = dateTime(
    result.year,
    result.month,
    result.monthDay,
    result.hour,
    result.minute,
    result.second,
    zone = utc(),
  )

proc sendFile*(ctx: Context, filename: string, dir = ".", headers: HttpHeaders = nil,
               downloadName = "", charset = "utf-8", bufsize = 4096) {.async.} =
    ## Responds to a context with a file
    # Implementation was based on staticFileResponse in https://github.com/planety/prologue/blob/devel/src/prologue/core/context.nim
    let filePath = dir / filename
    if not filePath.fileExists:
        ctx.status = Http404
        raise (ref NotFoundError)(msg: filename & " cannot be found")
        
    if fpUserRead notin filePath.getFilePermissions():
        ctx.status = Http403
        raise (ref UnauthorisedError)(msg: "You are unauthorised to access this file")

    let info = getFileInfo(filePath)
    if ctx.hasHeader("If-Modified-Since") and 
       ctx.getHeader("If-Modified-Since").parse(lastModifiedFormat, utc()) >= info.zeroWriteTime:
      # Return 304 if the file hasn't been modified since the client says they last got it
      ctx.send("", Http304)
    else:
      ctx.setHeader("Last-Modified", info.lastWriteTime.format(lastModifiedFormat, utc()))
      let (_, _, ext) = filePath.splitFile()
      {.gcsafe.}:
        ctx.setHeader("Content-Type", mimeDB.getMimeType(ext))
      # TODO: Stream the file
      # Check if the client allows us to compress the file
      if "gzip" in ctx.getHeader("Accept-Encoding", ""):
        ctx.sendCompressed(filePath.readFile())
      else:
        ctx.send(filePath.readFile())

