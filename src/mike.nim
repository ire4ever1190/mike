import std/options
import std/asyncdispatch
import std/strtabs
import std/httpcore

import mike/[
  dsl,
  context,
  helpers,
  ctxhooks,
  errors
]


import mike/bodyParsers/[
    form,
    multipart
]

import httpx
import websocketx

export asyncdispatch
export strtabs
export httpx
export websocketx
export options

export context
export dsl
export helpers
export form
export multipart
export ctxhooks
export httpcore
export errors


runnableExamples:
  "/" -> get:
    ctx.send("Hello world")

