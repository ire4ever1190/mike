
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
