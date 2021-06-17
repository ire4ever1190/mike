import src/mike
import src/mike/public
import strutils
import strformat
import tables
import nimprof

setPublic("/public")

type
    Person = ref object
        name: string
        age: int
    Test* = ref object of Context
        person: Person
        test: string


"/person/:name/:age" -> beforeGet(ctx: Test):
    echo "here"
    echo ctx.pathParams
    ctx.test = "hello my dude"
    ctx.person = Person(
        name: ctx.pathParams["name"],
        age: ctx.pathParams["age"].parseInt()
    )
    echo "now here"

"/person/:name/:age" -> get(ctx: Test):
    echo "here"
    echo ctx.test
    result = "hello"
    result = fmt"Hello {ctx.person.name} aged {ctx.person.age}"
    echo "now here"

"/test" -> get:
    ctx.response.body =  "hello sir"

run()
