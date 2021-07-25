import src/mike
import strutils
import strformat
import tables

#
# Simple routing
#

get "/":
    ctx.send "Mike is running!"

post "/hello":
    let names = ctx.json(seq[string])
    for name in names:
        echo name
    ctx.send "OK"

get "/shutdown":
    quit 0
#
# Context system
#

type
    Person = ref object
        name: string
        age: int
    Test* = ref object of Context
        person: Person
        test: string

beforeGet("/person/:name/:age") do (ctx: Test):
    echo "here"
    echo ctx.pathParams
    ctx.test = "hello my dude"
    ctx.person = Person(
        name: ctx.pathParams["name"],
        age: ctx.pathParams["age"].parseInt()
    )
    echo "now here"

get("/person/:name/:age") do (ctx: Test):
    echo "here"
    echo ctx.test
    result = "hello"
    result = fmt"Hello {ctx.person.name} aged {ctx.person.age}"
    echo "now here"


run()
