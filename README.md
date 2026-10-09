# shoal

<img src="assets/logo.png" alt="shoal logo" width="200" height="200">

my silly little ecs engine for odin and raylib :3

## contents
- [install](#install)
- [usage](#usage)

## install
clone this repo in your project directory

`git clone https://git.egfk.net/harper/shoal`

and import the package

```odin
import ecs "shoal/src"
```

## usage
first create a new app struct. this is where your systems and plugins live.

```odin
import ecs "shoal/src"

app: ecs.App
```

you can run your app with `run()`. run takes a reference to your app to run it's systems.

``` odin
main :: proc() {
  ecs.run(&app)
}
```

### systems
systems are procedures that run on set schedules

a schedule just determines when a producure runs\
schedules are:
- STARTUP
- UPDATE
- DRAW

`STARTUP` runs once at the start of an app\
`UPDATE` runs every frame\
`DRAW` runs every frame *after* update, and makes draw calls to raylib\

```odin
main :: proc() {
  ecs.add_system(&app, ecs.STARTUP, example_startup)
  ecs.add_system(&app, ecs.UPDATE, example_update)
}

example_startup :: proc() {
  // system that runs once
  // ...
}

example_update :: proc() {
  // system that runs every frame
  // ...
}
```

### components
components are just structs with data, and kept with other components of that type in `Storage`.\
create a new component

```odin
ExampleComponent :: struct {}
```

and create it's storage

```odin
Example: ecs.Storage(ExampleComponent)
```

### spawn entities
create a new entity with `spawn_entity()`

```odin
main :: proc() {
  entity := ecs.spawn_entity(&app)
}

```

and give it new components with `add_component()`

```odin
main :: proc() {
  ecs.add_component(entity, &Example) // make sure to pass a reference to the storage, not the component type
}
```

### query
since components are saved in storage next to their entity, you can loop through a Storage and pick out what you like

```odin
main :: proc() {
  for entity_id, component in ecs.slice(&Example) {
    //...
  }
}
```

or if you know your storage only has one entry use `single()`

```odin
main :: proc() {
  entity_id, component := ecs.single(&Example)
}
```
 ### plugins
plugins are just a procedure that takes `App` as a parameter, meaning it can make changes to `app`, just like main()

```odin
ExamplePlugin :: proc(app: ^App) {
  ecs.add_system(app, ecs.STARTUP, some_plugin_system)
}
```

```odin
main :: proc() {
  ecs.add_plugin(&app, ecs.DefaultPlugin)
  ecs.add_plugin(&app, ExamplePlugin)
}
```

plugins make your scripts very reuseable. in fact, much of shoal's default behaviors come from plugins via `DefaultPlugin()`
