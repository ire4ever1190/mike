
type 
  HandlerPos* = enum
    Pre    = "before" # Runs before main handler
    Middle = ""       # The main handler
    Post   = "after"  # Runs after the main handler

when not declared(decodeQuery):
  ## Reuse cgi's decoder for older nim versions
  from std/cgi import decodeData
  iterator decodeQuery*(data: string): tuple[key: string, value: string] {.raises: [].} =
    try:
      for (key, value) in decodeData(data):
        yield (key, value)
    except:
      discard
else:
  from std/uri import decodeQuery
  export decodeQuery
