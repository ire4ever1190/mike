
switch("path", "$projectDir/../src")
switch("d", "release")
switch("threads", "on")

when defined(orc):
    switch("deepcopy", "on")
    switch("gc", "orc")

when defined(profile):
    switch("profiler", "on")
    switch("stacktrace", "on")
