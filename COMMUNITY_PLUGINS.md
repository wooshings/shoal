# community plugin workflow

shoal's extensibility model is the plugin system: any feature can live as a standalone
`proc(app: ^App)` that registers systems, declares sets, and optionally spawns entities.
when a feature proves stable, it gets added to `DefaultPlugin` so every project gets it
out of the box.

## structure

feature plugins live in a directory alongside `src/`:

```
shoal/
  src/              core engine
  plugins/          community feature plugins (opt-in)
    ui/shoal.odin
    ui/rlmu.odin
    camera_plugin.odin
    input_plugin.odin
```

a plugin can be tested against any core version without breaking changes, and the core
stays clean until a feature earns its place in `DefaultPlugin`.

## workflow

1. build the feature as a plugin: a single `proc(app: ^App)` plus any components or
   helper procs it needs. place it in `plugins/`.

2. use it in your project: `ecs.add_plugin(&app, plugin.MyFeaturePlugin)` before
   `ecs.run(&app)`. if it needs core changes, those go in a standalone pull request to
   the core engine, not tied to the plugin.

3. when stable, merge into `DefaultPlugin`: add one line to `DefaultPlugin` in
   `src/systems.odin`. the plugin file can stay in `plugins/` or move into `src/`
   either way, `ecs.add_plugin(&app, ecs.DefaultPlugin)` now includes it.

## core engine changes

if a feature needs modifications to the core engine (new ecs methods, scheduling
semantics, component defaults), that is a standalone pull request to the core. it
should not reference or depend on any plugin. the plugin can land in `plugins/` and
use the new core once the core pr is merged, or sit on top of the core pr in the same
submission, but the two are independent concerns.

## writing a plugin

a plugin is a procedure that takes `^App`. from it you can:

- register systems: `ecs.add_system(app, schedule, system)`
- declare sets: `ecs.init_system_set(app, schedule, name)`
- anchor sets: `before("set")` / `after("set")`
- reach game data: `ecs.get_world(app)`

plugins execute once, in registration order, before `"startup"`. they are the only
place (besides `main()`) that holds `^App`.
