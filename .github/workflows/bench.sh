#!/usr/bin/bash
# Be on correct branch
git checkout $1

nimble install
# Compile the example
nim c -f -d:release example.nim
# Start it
./example &
# And then generate the output
oha --no-tui

# And stop the example server
pkill -P $$
