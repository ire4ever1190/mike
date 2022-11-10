import src/mike
import strutils
import strformat
import tables

#
# Simple routing
#

"/" -> get:
    ctx.send "Mike is running!"

"/hello" -> post:
    let names = ctx.json(seq[string])
    for name in names:
        echo name
    ctx.send "OK"

"/shutdown" -> get:
    quit 0

#
# Custom data
#

type
    Person = ref object of RootObj
        name: string
        age: int

"/person/:name/:age" -> beforeGet:
    echo ctx.pathParams
    ctx &= Person(
        name: ctx.pathParams["name"],
        age: ctx.pathParams["age"].parseInt()
    )

"/person/:name/:age" -> get:
    let person = ctx[Person]
    echo person
    ctx.send fmt"Hello {person.name} aged {person.age}"


run()
