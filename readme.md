
![image](https://github.com/ire4ever1190/mike/workflows/Tests/badge.svg)

This is a full rewrite of my old project with the same name.
The 1.x does not mean it is production ready, it just means it is incompatible with previous versions


### Routing

```nim
"/home" -> get:
    ctx.send "hello"
    
"/mike" -> post:
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
    ctx.send ctx.name # Returns the name that was set before
```
