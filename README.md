# shoal

⚠️ This library is still in early development and updating your projects may cause breaking changes.

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
systems are procedures that run on schedules. there are four root schedules,
and `run()` walks them in this order:

- `"startup"`: once, before the first frame (plugins run before this)
- `"update"`: every frame, your main logic (its walk ends with the
- `"draw"`: every frame, inside the raylib frame. this is where your draw calls go
- `"destroy"`: once, after the last frame, on shutdown

systems registered on the same schedule run in registration order: whoever was
`add_system()`ed first runs first, including the systems your plugins add.
`add_system` takes three arguments: `app`, the schedule name, and the system
proc:

```odin
main :: proc() {
  ecs.add_system(&app, "startup", setup_window)
  ecs.add_system(&app, "update", update_balls)
  ecs.add_system(&app, "draw", draw_balls)
  ecs.run(&app)
}
```

a root schedule name (`"startup"`, `"update"`, `"draw"`, `"destroy"`)
addresses that root's built-in `"default"` set, which is created on first
use. if your schedule name doesn't match a root, `add_system` panics at
registration time before the app ever runs, so typos can't hide.

#### system sets
a **system set** (child schedule) is a named group of systems within a root
schedule. you declare it with `init_system_set`, telling the engine which root
it lives under:

```odin
main :: proc() {
  ecs.init_system_set(&app, "startup", "window")
  ecs.init_system_set(&app, "startup", "spawn")
  ecs.init_system_set(&app, "update", "physics")
  ecs.init_system_set(&app, "draw", "render")
  ecs.init_system_set(&app, "draw", "hud")

  ecs.add_system(&app, "window", setup_window)
  ecs.add_system(&app, "spawn", spawn_balls)
  ecs.add_system(&app, "physics", update_balls)
  ecs.add_system(&app, "render", draw_balls)
  ecs.add_system(&app, "hud", show_framerate)
  ecs.run(&app)
}
```

a system can also take the world. declare it as `proc(world: ^ecs.World)` and
`run()` hands it the app's world, the same one holding every entity and
component

```odin
main :: proc() {
  ecs.add_system(&app, "startup", example_spawn)
}

example_spawn :: proc(world: ^ecs.World) {
  entity := ecs.spawn_entity(world) // the world, no global needed
  ecs.add_component(world, entity, ExampleComponent{...})
}
```

#### system sets
a **system set** (child schedule) is a named group of systems within a root
schedule. you declare it with `init_system_set`, telling the engine which root
it lives under:

```odin
main :: proc() {
  ecs.init_system_set(&app, "startup", "window")
  ecs.init_system_set(&app, "startup", "spawn")
  ecs.init_system_set(&app, "update", "physics")
  ecs.init_system_set(&app, "draw", "render")
  ecs.init_system_set(&app, "draw", "hud")

  ecs.add_system(&app, "window", setup_window)
  ecs.add_system(&app, "spawn", spawn_balls)
  ecs.add_system(&app, "physics", update_balls)
  ecs.add_system(&app, "render", draw_balls)
  ecs.add_system(&app, "hud", show_framerate)
  ecs.run(&app)
}
```

`add_system` resolves the schedule: a child name goes to the root that
declared it, a root name goes to its `"default"` set, anything else panics.
a set can't shadow a root name, and cross-root duplicate names panic too.

#### ordering: `before()` and `after()`
`init_system_set` optionally takes `before("other_set")` or `after("other_set")`
to control where a set is declared:

- `before("foo")` inserts the set before "foo" (or at the front if "foo"
  doesn't exist yet)
- `after("bar")` inserts the set after "bar" (or at the end if "bar" doesn't
  exist yet)
- no option, append after the sets declared so far

```odin
DefaultPlugin :: proc(app: ^App) {
  // "pre_draw" to the front, engine "default" after it, "post_draw" last
  ecs.init_system_set(app, "draw", "pre_draw", before("default"))
  ecs.init_system_set(app, "draw", "default", after("pre_draw"))
  ecs.add_system(app, "pre_draw", begin_frame)
  ecs.add_system(app, "draw", draw_sprite) // the root's built-in "default" set
  ecs.init_system_set(app, "draw", "post_draw")
  ecs.add_system(app, "post_draw", end_frame)
}
```

plugins run when `ecs.run()` starts, after `main()` has declared its sets,
so a plugin's own sets are anchored by name (before/after) rather than
registration order. that's what keeps shoal's `BeginDrawing`/`EndDrawing`
wrapped around your draw systems no matter when you declared things.

### components
components are plain structs. declare one and you're done. the data lives in the
world: every component type gets a storage inside it, created automatically the
first time you add that component to an entity. there's no global to declare
and no registration step

```odin
ExampleComponent :: struct {}
```

each world owns its own storages, keyed by the component's type: two worlds
never share data, and a zero `ecs.World{}` is ready to use.

### spawn entities
create a new entity with `spawn_entity()`, which hands out the next id from the
world's entity list. ids are never reused. systems get the world as a parameter;
in `main()` or a plugin it's `&app.world` (or `ecs.get_world(app)`)

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

either way the world's storage for that component type is created on the spot
if this is the first one

### query
since a world keeps components of one type together, you can loop through them
and pick out what you like. `slice()` and `slice_entity()` pair up by index:
`entities[i]` owns `components[i]`

```odin
example_system :: proc(world: ^ecs.World) {
  components := ecs.slice(world, ExampleComponent)
  entities := ecs.slice_entity(world, ExampleComponent)
  for v, i in components {
    e := entities[i]    // get entity that owns the component
  }
}
```

one caveat: `slice()` hands back the live array inside the world, not a copy,
so adding components afterwards can reallocate it out from under you. don't
hold one across `add_component()` calls.

or if you know only one entity has the component use `single()`

```odin
example_system :: proc(world: ^ecs.World) {
  component, entity_id := ecs.single(world, ExampleComponent)
}
```

`single()` panics with a message naming the component (`single: no entity has
component ExampleComponent`) if nobody in the world has it yet

and once you have an entity id, `get_component()` reaches into any component
type to get that entity's copy, handy for components that live alongside another
one (a sprite's `TransformComponent`, say)

```odin
example_system :: proc(world: ^ecs.World) {
  component, entity_id := ecs.single(world, ExampleComponent)
  other := ecs.get_component(world, entity_id, OtherExampleComponent)
}
```

`get_component()` panics with a message naming the entity and the component
(`get_component: entity 3 has no component OtherExampleComponent`) if that
entity never got that component. it used to hand back whatever was at index 0
of the storage instead, which crashed the app with a bounds error as soon as
nothing was there, the panic is the fixed version of that

if you're not sure whether the entity has it (probing a component another
system or plugin owns, say), ask first. `has_component()` answers yes/no, and
`try_get_component()` hands back the component and a flag, `(nil, false)`
instead of a panic when it's missing

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
plugins are a procedure that takes `^App` as a parameter, the one bit of
privilege over regular systems, which only ever see `^World`. a plugin can
register systems, schedules, and system sets on the app the same way main()
does, and reach the game data through `get_world(app)`

```odin
ExamplePlugin :: proc(app: ^App) {
  ecs.init_system_set(app, "update", "physics", before("default"))
  ecs.add_system(app, "physics", physics_system)

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

plugins make your scripts reusable. much of shoal's default behavior comes from
plugins via `DefaultPlugin()`

run() fires every plugin in the order you added them, once, before the
`"startup"` schedule, so everything they register is in place before anything
executes

### signals
signals are structs your systems can talk to each other with. one system writes
a signal with data, another system reads it later in the same frame, as long as
the reader runs before `signal_system` clears the buses (registered by
DefaultPlugin in the `"post_update"` set at the end of `"update"`, see the
caveat at the end of this section)

```odin
DamageEvent :: struct { amount: int }
```

`write()` queues a signal on a per-type bus. `read()` gives you back every
signal of that type written since the last clear (an empty slice if
there were none), so you can iterate it. reads don't consume, so any number of
systems can read the same signal and its data

```odin
attack :: proc() {
  ecs.write(DamageEvent{amount = 5})
}

// registered after attack in "update", so it sees the event the same frame
check_damage :: proc() {
  for e in ecs.read(DamageEvent) {
    fmt.println("took damage!", e.amount)
  }
}
```

you can also write an empty payload with the bare type: `ecs.write(DamageEvent)`

scheduling caveat: every system sees exactly the signals written since the last
`signal_system()` run, and that runs in the `"post_update"` set at the end of
`"update"`, *before* `"draw"`. so:

- systems running before `"post_update"` in the `"update"` walk (the default
  set and any sets main() declared before the plugin ran) see same-frame
  writes
- a `"draw"` system sees none of them, signal_system already cleared the bus.
  it only sees signals written after signal_system by an earlier system in the
  same frame (say, one `"draw"` system reacting to another's write)
- writes made after signal_system survive the rest of the frame and are picked
  up by the next frame's `"update"` systems, then cleared at the next frame's
  `"post_update"`. the next frame's `"draw"` never sees them either

### timers
timers are named countdowns. they live in a package global for now, deliberately
outside the world, since they're keyed by name rather than owned by an entity.
`start_timer()` starts one (or restarts one already stored under that name) and
`get_timer()` reads it back. anything that never started or already finished
reads back zeroed, so a nonzero `lifetime` means "still ticking"

```odin
example_system :: proc() {
  if ecs.get_timer("cooldown").lifetime != 0 {return} // still cooling down
  ecs.start_timer(0.5, "cooldown")
}
```

timers tick down every frame in `run_timers`, which `DefaultPlugin` registers at
`"update"`. the reset fires when the remaining lifetime drops to roughly one
frame's delta (it compares against a fresh `GetFrameTime()` call, so it can
reset a frame or two early) and resets the entry to `Timer{}`. that's the
auto-clear, and why `get_timer()` goes back to zero when you've waited it out.

on expiry a `TimerFired{name = ...}` signal is *meant* to be queued for
`read(TimerFired)`. wip: as written the reset zeroes the entry before the name
is read, so `TimerFired` currently never fires (reading the timers themselves
works fine). once that's fixed the usual signal caveat applies: a reader has
to run before `signal_system` clears the buses at `"post_update"`, see the end
of the [signals](#signals) section

### audio
shoal's `DefaultPlugin` wires in an audio plugin automatically: the device
opens at `"startup"`, playing streams are kept fed at `"update"` (a stream
nobody updates goes silent), and everything unloads at `"destroy"`. every
sound is a music stream under the hood, raylib decodes incrementally from
the compressed file, so nothing sits fully decoded in RAM. assets are cached
by path: the path is the handle, first call loads from disk and every call
after replays the loaded asset

```odin
main :: proc() {
  // audio comes with DefaultPlugin, no extra plugin to add
  ecs.play_sound("sounds/theme.ogg", true) // background music, loops
  ecs.play_sound("sounds/jump.wav")        // one-shot effect
  ecs.set_volume("sounds/jump.wav", 0.5)
  ecs.master_volume(0.8)
}
```

`play_sound` restarts from the top on repeat calls; `loop` makes it wrap at
the end instead of stopping. `stop`, `pause`, `resume`, and `set_volume`
control a stream by path. loading a path that doesn't exist panics with the
path, same fail-fast rule as registering on an undeclared schedule. paths
are relative to where you run the binary from

### ui
`shoal/ui` wraps microui with its own plugin. add it before any system that
wants to draw ui

```odin
import ui "shoal/ui"
import mu "vendor:microui"

main :: proc() {
  ecs.add_plugin(&app, ui.UIPlugin)
  ecs.add_system(&app, "draw", my_ui) // draw's built-in "default" set
}
```

`ui.UIPlugin` registers `init()` at `"draw"` (uploads microui's atlas texture),
`begin()` at `"draw"` (forwards raylib input and starts the frame), `end()` at
`"draw"` (renders the ui after all game drawing), frees the frame's temp
memory at `"draw"`, and `destroy()` at `"destroy"`.


your system builds the ui against the context `get_ctx()` hands back during the
frame

```odin
my_ui :: proc() {
  if mu.begin_window(ui.get_ctx(), "hello", {100, 100, 100, 100}) {
    defer mu.end_window(ui.get_ctx())
    mu.label(ui.get_ctx(), "Hello, world")
  }
}
```