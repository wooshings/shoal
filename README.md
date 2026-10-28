# shoal

<img src="assets/logo.png" alt="shoal logo" width="200" height="200">

my silly little ecs engine for odin and raylib :3

## contents
- [install](#install)
- [usage](#usage)

## install
clone this repo in your project directory

```git clone https://git.egfk.net/harper/shoal```

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

```odin
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
  components := ecs.slice(&Example)
  entities := ecs.slice_entity(&Example)
  for v, i in components {
    e := entities[i]    // get entity that owns the component
  }
}
```

or if you know your storage only has one entry use `single()`

```odin
main :: proc() {
  component, entity_id := ecs.single(&Example)
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

### signals
signals are structs your systems can talk to each other with. one system writes a signal with data, another system reads it later in the same frame — as long as the reader runs before `signal_system` clears the buses at POST_UPDATE (see the caveat at the end of this section)

```odin
DamageEvent :: struct { amount: int }
```

`write()` queues a signal on a per-type bus. `read()` gives you back every signal of that type written since the last POST_UPDATE (an empty slice if there were none), so you can iterate it. reads don't consume, so any number of systems can read the same signal and its data

```odin
attack :: proc() {
  ecs.write(DamageEvent{amount = 5})
}

// registered after attack in UPDATE, so it sees the event the same frame
check_damage :: proc() {
  for e in ecs.read(DamageEvent) {
    fmt.println("took damage!", e.amount)
  }
}
```

you can also write an empty payload with the bare type: `ecs.write(DamageEvent)`

scheduling caveat: every system sees exactly the signals written since the last `signal_system()` run, and that runs at POST_UPDATE — *before* PRE_DRAW/DRAW. so:

- systems running before POST_UPDATE (STARTUP/PRE_UPDATE/UPDATE/early POST_UPDATE) see same-frame writes
- a DRAW system sees none of them — POST_UPDATE already cleared the bus. it only sees signals written after POST_UPDATE by an earlier system in the same frame (say, one DRAW system reacting to another's write)
- writes made after POST_UPDATE survive the rest of the frame and are picked up by the next frame's PRE_UPDATE/UPDATE systems, then cleared at the next POST_UPDATE — so the next frame's DRAW never sees them either
