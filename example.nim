import src/mike
import src/mike/public
import strutils
import strformat

setPublic("/public")

type
    Person = ref object
        name: string
        age: int
    Test* = ref object of Context
        person: Person
        test: string


"/hello" -> beforeGet(ctx: Test):
    echo "beforehand"

"/hello" -> get(ctx: Test):
    result = "hello, "

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

"/test" -> beforeGet:
    ctx.response.body = "hello "

"/test" -> get:
    ctx.response.body &= "sir"

run()
