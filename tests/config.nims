
switch("path", "$projectDir/../src")
switch("threads", "on")
warning("BareExcept", false)

when defined(profile):
    switch("profiler", "on")
    switch("stacktrace", "on")

