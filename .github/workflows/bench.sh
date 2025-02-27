#!/usr/bin/bash
# Be on correct branch
git checkout $1

nimble install
# Compile the example
nim c -f -d:release example.nim
# Start it
./example &
# And then generate the output
oha --no-tui -z 30sec -j http://127.0.0.1:8080/person/foo/9 > "${1}.json"

# And stop the example server
pkill -P $$
