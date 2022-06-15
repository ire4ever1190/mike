
switch("path", "$projectDir/../src")
switch("d", "release")
switch("threads", "on")


when defined(profile):
    switch("profiler", "on")
    switch("stacktrace", "on")
