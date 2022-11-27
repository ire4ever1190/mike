
switch("path", "$projectDir/../src")
switch("threads", "on")
#switch("", "silent")

when defined(profile):
    switch("profiler", "on")
    switch("stacktrace", "on")

