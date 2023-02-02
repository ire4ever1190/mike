
switch("path", "$projectDir/../src")
switch("threads", "on")
when (NimMajor, NimMinor) >= (1, 7):
  warning("BareExcept", false)

when defined(profile):
    switch("profiler", "on")
    switch("stacktrace", "on")

