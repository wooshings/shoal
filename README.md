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

a schedule just determines when a procedure runs\
there are 8 of them, and `run()` walks them in this order:

- `STARTUP` — once, before the first frame
- `PRE_UPDATE` — every frame, first thing
- `UPDATE` — every frame, your main logic
- `POST_UPDATE` — every frame, last stop before drawing (`signal_system` clears the signal buses here)
- `PRE_DRAW` — every frame, opens the raylib frame (`DefaultPlugin` calls `BeginDrawing` + clears the background here)
- `DRAW` — every frame, inside the frame — this is where your raylib draw calls go
- `POST_DRAW` — every frame, closes the raylib frame (`DefaultPlugin` calls `EndDrawing` here)
- `DESTROY` — once, after the loop exits (`DefaultPlugin` calls `CloseWindow` here)

so: `STARTUP` runs once up front, the six update/draw ones run every frame in that order, `DESTROY` runs once when the window closes.

systems registered on the same schedule run in registration order — whoever was `add_system()`ed first runs first (that includes the systems your plugins add, so `add_plugin(&app, ecs.DefaultPlugin)` before your own systems means shoal's defaults run first).

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

shoal ships a few built-ins already declared as globals, so there's nothing to create — just pass `&ecs.Window`, `&ecs.Cursor`, `&ecs.Sprite` or `&ecs.Transform`. `DefaultPlugin` reads and writes them: it opens the window from `Window`, keeps `Cursor` on the mouse, and draws every `Sprite` at its `Transform`.

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

or fill it in on the spot with the data overload

```odin
main :: proc() {
  ecs.add_component(entity, &Example, ExampleComponent{...})
}
```

### query
since components are saved in storage next to their entity, you can loop through a Storage and pick out what you like. `slice()` and `slice_entity()` pair up by index: `entities[i]` owns `components[i]`

```odin
main :: proc() {
  components := ecs.slice(&Example)
  entities := ecs.slice_entity(&Example)
  for v, i in components {
    e := entities[i]    // get entity that owns the component
  }
}
```

one caveat: `slice()` hands back the storage's live array, not a copy, so adding components afterwards can reallocate it out from under you — don't hold one across `add_component()` calls.

or if you know your storage only has one entry use `single()`

```odin
main :: proc() {
  component, entity_id := ecs.single(&Example)
}
```

and once you have an entity id, `get_component()` reaches into any storage to get that entity's copy of the component — handy for components that live alongside another one (a sprite's `Transform`, say)

```odin
main :: proc() {
  component, entity_id := ecs.single(&Example)
  other := ecs.get_component(entity_id, &OtherExample)
}
```

no existence check though: only ask for entities you know are in that storage.
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

run() fires every plugin in the order you added them, once, before the STARTUP systems — so everything they register is in place before anything executes

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

### timers
timers are named countdowns. `start_timer()` starts one (or restarts one already stored under that name), and `get_timer()` reads it back — anything that never started or already finished reads back zeroed, so a nonzero `lifetime` means "still ticking"

```odin
example_system :: proc() {
  if ecs.get_timer("cooldown").lifetime != 0 {return} // still cooling down
  ecs.start_timer(0.5, "cooldown")
}
```

timers tick down every frame in `run_timers`, which `DefaultPlugin` registers at UPDATE. when one runs out its entry is reset to `Timer{}` — that's the auto-clear, and why `get_timer()` goes back to zero when you've waited it out.

on expiry a `TimerFired{name = ...}` signal is *meant* to be queued for `read(TimerFired)` — wip: as written the reset zeroes the entry before the name is read, so `TimerFired` currently never fires (reading the timers themselves works fine). once that's fixed the usual signal caveat applies: a reader has to run before `signal_system` clears the buses at POST_UPDATE, see the end of the [signals](#signals) section

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

`ui.UIPlugin` registers `init()` at STARTUP (uploads microui's atlas texture), `begin()` at PRE_DRAW (forwards raylib input and starts the frame), frees the frame's temp memory and runs `end()` at POST_DRAW (renders the ui), and `destroy()` at DESTROY.

your system builds the ui against the context `get_ctx()` hands back during the frame

```odin
my_ui :: proc() {
  if mu.begin_window(ui.get_ctx(), "hello", {100, 100, 100, 100}) {
    defer mu.end_window(ui.get_ctx())
    mu.label(ui.get_ctx(), "Hello, world")
  }
}
```

### tween
wip: tweens don't do anything yet. `tween.odin` ships `Tween`, `start_tween()`, `create_tween()` (a stub that returns an empty `Tween` and ignores its arguments), `update_tween_system()` (empty, and no schedule registers it) and a few sine easing helpers nothing calls — don't build on it. the `EASE_IN`/`EASE_OUT`/`EASE_IN_OUT` constants are ids for the unused `Tween.ease` field.
