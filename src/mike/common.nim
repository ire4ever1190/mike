type 
    HandlerPos* = enum
        Pre    = "before" # Runs before main handler
        Middle = ""       # The main handler
        Post   = "after"  # Runs after the main handler