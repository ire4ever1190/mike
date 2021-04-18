
This is a full rewrite of my old project with the same name.
The 1.x does not mean it is stable, it just means it is incompatible with previous versions

check out `example.nim` for actual examples

### Routing

```nim
"/home" -> get:
    return "hello"
    
"/mike" -> get:
    ctx.response.code = Http427
    ctx.response.body = "The worst framework around"
```