
This is a full rewrite of my old project with the same name.
The 1.x does not mean it is stable, it just means it is incompatible with previous versions

check out `example.nim` for actual examples

### Routing

```nim
"/home" -> get:
    return "hello"
    
"/mike" -> get:
    ctx.send("The worst framework around", Http427)
```


### Context
You can define a context to keep data between middlewares

```nim
type
    Person = object of Context
        name: string
        
"/home/:name" -> beforeGet(ctx: Person):
    # You could fetch the user from the database or something
    ctx.name = ctx.pathParams["name"]
    
"/home/:name" -> get(ctx: Person):
    return ctx.name # Returns the name that was set before
```