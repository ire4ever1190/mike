import std/[
  mimetypes,
  os,
  httpcore,
  json,
  asyncdispatch,
  times
]
import ../context
import ../response as res
import ../errors
import response
import httpx
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

proc send*(ctx: Context, body: string, code: HttpCode, extraHeaders: HttpHeaders = nil) =
    ## Responds to a context and overwrites the status code
    ctx.response.code = code
    ctx.response.body = body
    ctx.request.send(
        body = ctx.response.body,
        code = ctx.response.code,
        headers = (ctx.response.headers & extraHeaders).toString()
    )
    ctx.handled = true

proc send*[T](ctx: Context, obj: T, code = Http200, extraHeaders: HttpHeaders = nil) =
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

proc send*(ctx: Context, body: string, extraHeaders: HttpHeaders = nil) =
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

proc sendFile*(ctx: Context, filename: string, dir = ".", headers: HttpHeaders = nil,
               downloadName = "", charset = "utf-8", bufsize = 4096) {.async.} =
    ## Responds to a context with a file
    # Implementation was based on staticFileResponse in https://github.com/planety/prologue/blob/devel/src/prologue/core/context.nim
    let filePath = dir / filename
    if not filePath.fileExists:
        ctx.status = Http404
        raise (ref NotFoundError)(msg: filename & " cannot be found")
    if fpUserRead notin filename.getFilePermissions():
        ctx.status = Http403
        raise (ref UnauthorisedError)(msg: "You are unauthorised to access this file")

    let info = getFileInfo(filePath)
    ctx.setHeader("Content-Length", $info.size)
    ctx.setHeader("Last-Modified", info.lastWriteTime.format(lastModifiedFormat, utc()))
    let (_, _, ext) = filename.splitFile()
    {.gcsafe.}:
      ctx.setHeader("Content-Type", mimeDB.getMimeType(ext))
    # TODO: Stream the file
    ctx.send(filePath.readFile())

