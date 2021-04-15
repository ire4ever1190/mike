
switch("path", "$projectDir/../src")
switch("d", "release")
switch("gc", "orc")
switch("threads", "on")
switch("deepcopy", "on")
when defined(profile):
    switch("profiler", "on")
    switch("stacktrace", "on")
