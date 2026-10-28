package shoal

import rl "vendor:raylib"

// the engine backend: systems grouped by schedule id (see the STARTUP..DESTROY
// constants), the plugins that run before everything else, and the world,
// holding every entity and component at a lower scope than the app itself. only
// main() and plugins ever see an ^App; systems are handed ^World and so
// structurally can't reach the registration machinery (add_system, plugins,
// run)
App :: struct {
	systems: map[int][dynamic]System,
	plugins: [dynamic]proc(app: ^App),
	world:   World,
}

// a system in either shape add_system accepts: a plain proc(), or one that
// takes the world as proc(world: ^World). stored uniformly so run() can give
// every system the same dispatch. more parameter shapes can go here later
System :: union {
	proc(),
	proc(world: ^World),
}

// register a system on a schedule (one of the STARTUP..DESTROY constants).
// systems on the same schedule run in registration order, every time that
// schedule comes around. a system is either a plain proc(), or takes the
// world as proc(world: ^World) when it needs to spawn entities or touch
// components
add_system :: proc {
	add_plain_system,
	add_world_system,
}

@(private)
add_plain_system :: proc(app: ^App, schedule: int, system: proc()) {
	if _, ok := app.systems[schedule]; !ok {
		app.systems[schedule] = [dynamic]System{}
	}
	append(&app.systems[schedule], System(system))
}

@(private)
add_world_system :: proc(app: ^App, schedule: int, system: proc(world: ^World)) {
	if _, ok := app.systems[schedule]; !ok {
		app.systems[schedule] = [dynamic]System{}
	}
	append(&app.systems[schedule], System(system))
}

// register a plugin: a proc that gets ^App, the one privilege over regular
// systems, which only ever see ^World. a plugin can add_system/add_plugin
// the same way main() would, and reach the game data through get_world. run()
// executes plugins in registration order, once, before the STARTUP systems.
// the systems a plugin adds can be plain proc() or take the world, same as
// any other add_system call
add_plugin :: proc(app: ^App, plugin: proc(app: ^App)) {
	append(&app.plugins, plugin)
}

// everything registered on a schedule, in registration order, or an empty
// list if nothing was added. each entry is a System union: switch on it to
// tell a plain proc() from a proc(world: ^World). this is what run() walks
// each frame
get_system :: proc(app: ^App, schedule: int) -> [dynamic]System {
	if systems, ok := app.systems[schedule]; ok && len(systems) > 0 {
		return systems
	}
	return [dynamic]System{}
}

// the world tucked inside the app, the ^App equivalent of the ^World
// systems get handed. plugins use it to spawn entities or add components
// before the frame loop starts; regular systems never need it, run() gives
// them the same world directly
get_world :: proc(app: ^App) -> ^World {
	return &app.world
}

// run every plugin (in registration order), then the STARTUP systems once,
// then the frame loop: PRE_UPDATE -> UPDATE -> POST_UPDATE -> PRE_DRAW ->
// DRAW -> POST_DRAW, over and over until rl.WindowShouldClose() says stop,
// and finally the DESTROY systems. world systems get handed the app's own
// world, the same one run() is holding. there's no second copy
run :: proc(app: ^App) {
	for p in app.plugins {
		p(app)
	}
	for s in get_system(app, STARTUP) {run_system(app, s)}

	for !rl.WindowShouldClose() {
		for s in get_system(app, PRE_UPDATE) {run_system(app, s)}
		for s in get_system(app, UPDATE) {run_system(app, s)}
		for s in get_system(app, POST_UPDATE) {run_system(app, s)}
		for s in get_system(app, PRE_DRAW) {run_system(app, s)}
		for s in get_system(app, DRAW) {run_system(app, s)}
		for s in get_system(app, POST_DRAW) {run_system(app, s)}
	}

	for s in get_system(app, DESTROY) {run_system(app, s)}
}

// hand a stored system its call: a plain one just runs, a world one gets the
// app's world
@(private)
run_system :: proc(app: ^App, system: System) {
	switch s in system {
	case proc():
		s()
	case proc(world: ^World):
		s(&app.world)
	}
}
