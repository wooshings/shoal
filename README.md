# shoal

<img src="assets/logo.png" alt="shoal logo" width="200" height="200">

my silly little ecs engine for odin and raylib :3

## contents
- [install](#install)
- [usage](#usage)
  - [systems](#systems)
  - [components](#components)
  - [spawn entities](#spawn-entities)
  - [query](#query)
  - [plugins](#plugins)
  - [signals](#signals)
  - [timers](#timers)
  - [ui](#ui)
  - [tween](#tween)

## install
clone this repo in your project directory

```sh
git clone https://git.egfk.net/harper/shoal
```

and import the package

```odin
import ecs "shoal/src"
```

## usage
first create a new app struct. it holds your systems and plugins, and tucked
inside it a `World` holding every entity and component (your game data).
systems never see the app itself, only the world

```odin
import ecs "shoal/src"

main :: proc() {
  app: ecs.App
}
```

you can run your app with `run()`. run takes a pointer to your app and drives its systems.

```odin
main :: proc() {
  ecs.run(&app)
}
```

### systems
systems are procedures that run on set schedules

a schedule determines when a procedure runs\
there are 4 of them, and `run()` walks them in this order:

- `STARTUP`: once, before the first frame
- `UPDATE`: every frame, your main logic
- `DRAW`: every frame, inside the frame. this is where your raylib draw calls go
- `DESTROY`: once, after the last frame, on shutdown

systems registered on the same schedule run in registration order: whoever was `add_system()`ed first runs first, including the systems your plugins add. plugins themselves always run once before *all* the `STARTUP` systems, no matter when you `add_plugin()` them, so adding `add_plugin(&app, ecs.DefaultPlugin)` first doesn't change *when* DefaultPlugin runs. it just puts shoal's defaults at the front of each schedule, which is still a good habit.

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

a system can also take the world. declare it as `proc(world: ^ecs.World)` and `run()` hands it the app's world, the same one holding every entity and component. that's all a system ever gets: systems structurally can't reach the app itself (add_system, plugins, run); only plugins and `main()` ever hold an `^App`

```odin
main :: proc() {
  ecs.add_system(&app, ecs.STARTUP, example_spawn)
}

example_spawn :: proc(world: ^ecs.World) {
  entity := ecs.spawn_entity(world) // the world, no global needed
  ecs.add_component(world, entity, ExampleComponent{...})
}
```

plain `proc()` systems work exactly as before. only ask for the world parameter when you actually need it

### components
components are plain structs. declare one and you're done. the data lives in the world: every component type gets a storage inside it, created automatically the first time you add that component to an entity. there's no global to declare and no registration step

```odin
ExampleComponent :: struct {}
```

each world owns its own storages, keyed by the component's type: two worlds never share data, and a zero `ecs.World{}` is ready to use.

### spawn entities
create a new entity with `spawn_entity()`, which hands out the next id from the world's entity list. ids are never reused. systems get the world as a parameter; in `main()` or a plugin it's `&app.world` (or `ecs.get_world(app)`)

```odin
example_spawn :: proc(world: ^ecs.World) {
  entity := ecs.spawn_entity(world)
}

```

and give it new components with `add_component()`

```odin
example_spawn :: proc(world: ^ecs.World) {
  entity := ecs.spawn_entity(world)
  ecs.add_component(world, entity, ExampleComponent) // just the type: a zero-initialized component
}
```

or fill it in on the spot by passing data instead

```odin
example_spawn :: proc(world: ^ecs.World) {
  entity := ecs.spawn_entity(world)
  ecs.add_component(world, entity, ExampleComponent{...})
}
```

either way the world's storage for that component type is created on the spot if this is the first one

### query
since a world keeps components of one type together, you can loop through them and pick out what you like. `slice()` and `slice_entity()` pair up by index: `entities[i]` owns `components[i]`

```odin
example_system :: proc(world: ^ecs.World) {
  components := ecs.slice(world, ExampleComponent)
  entities := ecs.slice_entity(world, ExampleComponent)
  for v, i in components {
    e := entities[i]    // get entity that owns the component
  }
}
```

one caveat: `slice()` hands back the live array inside the world, not a copy, so adding components afterwards can reallocate it out from under you. don't hold one across `add_component()` calls.

or if you know only one entity has the component use `single()`

```odin
example_system :: proc(world: ^ecs.World) {
  component, entity_id := ecs.single(world, ExampleComponent)
}
```

`single()` panics with a message naming the component (`single: no entity has component ExampleComponent`) if nobody in the world has it yet

and once you have an entity id, `get_component()` reaches into any component type to get that entity's copy, handy for components that live alongside another one (a sprite's `TransformComponent`, say)

```odin
example_system :: proc(world: ^ecs.World) {
  component, entity_id := ecs.single(world, ExampleComponent)
  other := ecs.get_component(world, entity_id, OtherExampleComponent)
}
```

`get_component()` panics with a message naming the entity and the component (`get_component: entity 3 has no component OtherExampleComponent`) if that entity never got that component. it used to hand back whatever was at index 0 of the storage instead, which crashed the app with a bounds error as soon as nothing was there — the panic is the fixed version of that

if you're not sure whether the entity has it (probing a component another system or plugin owns, say), ask first. `has_component()` answers yes/no, and `try_get_component()` hands back the component and a flag, `(nil, false)` instead of a panic when it's missing

```odin
example_system :: proc(world: ^ecs.World) {
  if ecs.has_component(world, entity_id, OtherExampleComponent) {
    // ...
  }

  if other, ok := ecs.try_get_component(world, entity_id, OtherExampleComponent); ok {
    // use other
  }
}
```

### plugins
plugins are a procedure that takes `^App` as a parameter, the one bit of privilege over regular systems, which only ever see `^World`. a plugin can register systems and plugins on the app the same way main() does, and reach the game data through `get_world(app)`

```odin
ExamplePlugin :: proc(app: ^App) {
  ecs.add_system(app, ecs.STARTUP, some_plugin_system)

  entity := ecs.spawn_entity(ecs.get_world(app)) // same world the systems will get
  ecs.add_component(ecs.get_world(app), entity, ExampleComponent{...})
}
```

```odin
main :: proc() {
  ecs.add_plugin(&app, ecs.DefaultPlugin)
  ecs.add_plugin(&app, ExamplePlugin)
}
```

plugins make your scripts reusable. much of shoal's default behavior comes from plugins via `DefaultPlugin()`

run() fires every plugin in the order you added them, once, before the STARTUP systems, so everything they register is in place before anything executes

### signals
signals are structs your systems can talk to each other with. one system writes a signal with data, another system reads it later in the same frame, as long as the reader runs before `signal_system` clears the buses at POST_UPDATE (see the caveat at the end of this section)

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

scheduling caveat: every system sees exactly the signals written since the last `signal_system()` run, and that runs at POST_UPDATE, *before* PRE_DRAW/DRAW. so:

- systems running before POST_UPDATE (STARTUP/PRE_UPDATE/UPDATE/early POST_UPDATE) see same-frame writes
- a DRAW system sees none of them, POST_UPDATE already cleared the bus. it only sees signals written after POST_UPDATE by an earlier system in the same frame (say, one DRAW system reacting to another's write)
- writes made after POST_UPDATE survive the rest of the frame and are picked up by the next frame's PRE_UPDATE/UPDATE systems, then cleared at the next POST_UPDATE. the next frame's DRAW never sees them either

### timers
timers are named countdowns. they live in a package global for now, deliberately outside the world, since they're keyed by name rather than owned by an entity. `start_timer()` starts one (or restarts one already stored under that name) and `get_timer()` reads it back. anything that never started or already finished reads back zeroed, so a nonzero `lifetime` means "still ticking"

```odin
example_system :: proc() {
  if ecs.get_timer("cooldown").lifetime != 0 {return} // still cooling down
  ecs.start_timer(0.5, "cooldown")
}
```

timers tick down every frame in `run_timers`, which `DefaultPlugin` registers at UPDATE. the reset fires when the remaining lifetime drops to roughly one frame's delta (it compares against a fresh `GetFrameTime()` call, so it can reset a frame or two early) and resets the entry to `Timer{}`. that's the auto-clear, and why `get_timer()` goes back to zero when you've waited it out.

on expiry a `TimerFired{name = ...}` signal is *meant* to be queued for `read(TimerFired)`. wip: as written the reset zeroes the entry before the name is read, so `TimerFired` currently never fires (reading the timers themselves works fine). once that's fixed the usual signal caveat applies: a reader has to run before `signal_system` clears the buses at POST_UPDATE, see the end of the [signals](#signals) section

### ui
`shoal/ui` wraps microui with its own plugin. add it before any system that wants to draw ui

```odin
import ui "shoal/ui"
import mu "vendor:microui"

main :: proc() {
  ecs.add_plugin(&app, ui.UIPlugin)
  ecs.add_system(&app, ecs.DRAW, my_ui)
}
```

`ui.UIPlugin` registers `init()` at STARTUP (uploads microui's atlas texture), `begin()` at PRE_DRAW (forwards raylib input and starts the frame), `end()` at LATE_DRAW (renders the ui after all game drawing, inside the raylib frame), frees the frame's temp memory at POST_DRAW, and `destroy()` at DESTROY.

your system builds the ui against the context `get_ctx()` hands back during the frame

```odin
my_ui :: proc() {
  if mu.begin_window(ui.get_ctx(), "hello", {100, 100, 100, 100}) {
    defer mu.end_window(ui.get_ctx())
    mu.label(ui.get_ctx(), "Hello, world")
  }
}
```
