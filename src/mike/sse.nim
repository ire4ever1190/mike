import ./context
import ./helpers
import std/[options, strutils, asyncdispatch]
import pkg/casserole

type
  SSEEvent* = object
    ## Stores an event that can be sent to a client
    ## See [here](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#fields) for more info on the fields
    event*: Option[string] ## Name of the event. If missing then a data only message is sent
    data*: string ## Data to send
    id*: Option[string] ## ID of this event

proc startSSE*(ctx: Context, retry = 3000) =
  ## Allows you to start sending [server sent events](https://en.wikipedia.org/wiki/Server-sent_events) to the client.
  ##
  ## * **retry**: How quickly in milliseconds the client should try and reconnect
  ctx.setHeader("Content-Type", "text/event-stream")
  ctx.setHeader("X-Accel-Buffering", "no") # Stops proxies from buffering
  ctx.setHeader("Cache-Control", "no-store")
  ctx.startChunking()
  ctx.sendChunk("retry: " & $retry & "\n\n")

proc stopSSE*(ctx: Context) =
  ## Tells the client that the events have stopped
  ctx.sendChunk("")

proc sendEvent*(ctx: Context, event: SSEEvent) =
  ## Sends an event with associated data. **event** isn't sent if it's empty (Body is still sent though)
  var payload = ""
  template field(name: string, data: string) = payload &= name & ": " & data & '\n'
  if Some(name) ?== event.event:
    field("event", name)
  if Some(id) ?== event.id:
    field("id", id)

  for line in event.data.splitLines():
    field("data", line)
  payload &= '\n'

  ctx.sendChunk(payload)

proc sendEvent*(ctx: Context, event, data: string) =
  ## Helper for sending data
  ctx.sendEvent(SSEEvent(event: if event == "": none(string) else: some(event), data: data))

proc sendResponse*(ctx: Context, iter: iterator (): SSEEvent {.closure.}) {.async, gcsafe.} =
  ## Generic handler for futures, passes it off to a `sendResponse` book that matches for `T`
  ctx.startSSE()
  defer: ctx.stopSSE()
  {.gcsafe.}:
    for event in iter():
      ctx.sendEvent(event)
      await sleepAsync(0) # Make sure iterator doesn't hog everything
