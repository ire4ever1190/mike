
switch("path", "$projectDir/../src")
switch("d", "release")
switch("gc", "arc")
when defined(profile):
    switch("profiler", "on")
    switch("stacktrace", "on")
