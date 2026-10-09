# shoal

my silly little ecs engine for odin and raylib :3

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

### component
components are just structs with data, and kept with other components of that type in `Storage`.
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
