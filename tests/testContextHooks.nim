import mike
import utils

import std/[
  unittest,
  json,
  httpclient,
  strformat,
  strutils
]

"/item/:id" -> get(id: int8):
  ctx.send $id

"/person/:name" -> get(name: string):
  ctx.send name

"/path/:name" -> get(name: Path[string]):
  ctx.send name

"/headers/1" -> get(something: Header[string]):
  ctx.send something

"/headers/2" ->  get(something: Header[int]):
  ctx.send $something

"/headers/3" -> get(something: Header[Option[int]]):
  if something.isSome:
    ctx.send "Has value: " & $something.get()
  else:
    ctx.send "No value"

"/headers/4" -> get(stuff: Header[seq[string]]):
  ctx.send(stuff.join(", "))

type
  Person = object
    name*: string
    age*: int

"/json/1" -> post(person: Json[Person]):
  ctx.send person

"/json/2" -> post(person: Json[Option[Person]]):
  if person.isSome:
    ctx.send "Has value: " & person.get().name
  else:
    ctx.send "No value"

type
  Auth = ref object of RootObj
    username, password: string

"/data/^_" -> beforeGet(username, password: Header[Option[string]]):
  if username.isSome and password.isSome:
    ctx &= Auth(
      username: username.get(),
      password: password.get()
    )

"/data/1" -> get(auth: Data[Auth]):
  ctx.send fmt"{auth.username}:{auth.password}"

"/data/2" -> get(auth: Data[Option[Auth]]):
  if auth.isSome:
    ctx.send "Logged in"
  else:
    ctx.send "Logged out"

"/form/1" -> get(person: Form[Person]):
  ctx.send person

type
  Something = object
    page: int
    full: bool

"/form/2" -> get(smth: Form[Something]):
  ctx.send smth.full

"/form/3" -> get(person: Form[Option[Person]]):
  if person.isSome:
    ctx.send person
  else:
    ctx.send "No person"

"/query/1" -> get(name: Query[string]):
  ctx.send name

"/query/2" -> get(age: Query[Option[float]]):
  ctx.send age.get(-1'f)

"/query/3" -> get(exists: Query[bool]):
  ctx.send exists

runServerInBackground()

proc errorMsg(x: httpclient.Response): string =
  x.body.parseJson()["detail"].getStr()

suite "Path params":
  test "Parse int":
    check get("/item/9").body == "9"

  test "Fails on non integer":
    let resp = get("/item/9.9")
    let json = resp.body.parseJson()
    check:
      resp.code == Http400
      json["kind"].getStr() == "BadRequestError"
      json["detail"].getStr() == "Value '9.9' is not in right format for int8"

  test "Fails when to large":
    let highVal = $(int8.high.int + 1)
    let resp = get("/item/" & highVal)
    check:
      resp.code == Http400
      resp.errorMsg == fmt"Value '{highVal}' is out of range for int8"

  test "Parse string":
    check get("/person/me").body == "me"

  test "Path[] isn't inserted if already path":
    check get("/path/me").body == "me"

suite "Header param":
  test "Parse string":
    check get("/headers/1", {
      "something": "Hello"
    }).body == "Hello"

  test "Missing header":
    let resp = get("/headers/1")
    check resp.code == Http400
    check resp.errorMsg == "Missing header 'something' in request"

  test "Parse int":
    check get("/headers/2", {
      "something": "2"
    }).body == "2"

  test "Option can have missing value":
    let resp = get("/headers/3")
    check:
      resp.code == Http200
      resp.body == "No value"

  test "Option can have value":
    let resp = get("/headers/3", {
      "something": "100"
    })
    check:
      resp.code == Http200
      resp.body == "Has value: 100"

  test "Sequence of values":
    let resp = get("/headers/4", {
        "stuff": "Hello",
        "stuff": "World",
        "other": "Bar",
        "stuff": "foo"
    })
    check resp.body == "Hello, World, foo"

suite "JSON":
  let person = Person(
    name: "John Doe",
    age: 42
  )
  test "Can parse body":
    check post("/json/1", person).to(Person) == person

  test "Allow empty body":
    check post("/json/2", "").body == "No value"

  test "Allow some body":
    check post("/json/2", person).body == "Has value: John Doe"

suite "Data":
  let headers = {
    "username": "foo",
    "password": "bar"
  }

  test "Can get data":
    check get("/data/1", headers).body == "foo:bar"

  test "Throws error when no data":
    check get("/data/1").code == Http500

  test "None value":
    check get("/data/2").body == "Logged out"

  test "Some value":
    check get("/data/2", headers).body == "Logged in"

suite "Form":
  const personForm = "age=42&name=Foo"
  test "Get form object":
    check get("/form/1?" & personForm).body.parseJson() == %* {
      "age": 42,
      "name": "Foo"
    }

  test "Bool parameters":
    check get("/form/2?page=9&full=1").body == "true"
    check get("/form/2?page=9&full=0").body == "false"

  test "Error on missing key":
    let resp = get("/form/2?&full")
    check resp.errorMsg == "'page' missing in form"
    check resp.code == Http400

  test "Optional object":
    check get("/form/3?" & personForm).body.parseJson() == %* {
      "age": 42,
      "name": "Foo"
    }
    check get("/form/3").body == "No person"

suite "Query param":
  test "Can get query param":
    check get("/query/1?name=Foo").body == "Foo"

  test "Option[T]":
    check get("/query/2?age=2.9").body == "2.9"
    check get("/query/2").body == "-1.0"

  test "Error when missing":
    let resp = get("/query/1")
    check:
      resp.code == Http400
      resp.errorMsg == "'name' missing in query parameters"

  test "Parse bools":
    check get("/query/3?exists=1").body == "true"
