package shoal

import rl "vendor:raylib"

// the app itself: systems grouped by schedule id (see the STARTUP..DESTROY
// constants), the plugins that run before everything else, and the list of
// every entity id handed out by spawn_entity
App :: struct {
	systems:  map[int][dynamic]proc(),
	plugins:  [dynamic]proc(app: ^App),
	entities: [dynamic]Entity,
}

// register a system on a schedule (one of the STARTUP..DESTROY constants).
// systems on the same schedule run in registration order, every time that
// schedule comes around
add_system :: proc(app: ^App, schedule: int, system: proc()) {
	if _, ok := app.systems[schedule]; !ok {
		app.systems[schedule] = [dynamic]proc(){}
	}
	append(&app.systems[schedule], system)
}

// register a plugin: a proc that gets ^App and can add_system/add_plugin just
// like main() would. run() executes them in registration order, once, before
// the STARTUP systems
add_plugin :: proc(app: ^App, plugin: proc(app: ^App)) {
	append(&app.plugins, plugin)
}

// everything registered on a schedule, in registration order — or an empty
// list if nothing was added. this is what run() iterates each frame
get_system :: proc(app: ^App, schedule: int) -> [dynamic]proc() {
	if systems, ok := app.systems[schedule]; ok && len(systems) > 0 {
		return systems
	}
	return [dynamic]proc(){}
}

// run every plugin (in registration order), then the STARTUP systems once,
// then the frame loop: PRE_UPDATE -> UPDATE -> POST_UPDATE -> PRE_DRAW ->
// DRAW -> POST_DRAW, over and over until rl.WindowShouldClose() says stop,
// and finally the DESTROY systems
run :: proc(app: ^App) {
	for p in app.plugins {
		p(app)
	}
	for i in app.systems[STARTUP] {i()}

	for !rl.WindowShouldClose() {
		for i in get_system(app, PRE_UPDATE) {i()}
		for i in get_system(app, UPDATE) {i()}
		for i in get_system(app, POST_UPDATE) {i()}
		for i in get_system(app, PRE_DRAW) {i()}
		for i in get_system(app, DRAW) {i()}
		for i in get_system(app, POST_DRAW) {i()}
	}

	for i in get_system(app, DESTROY) {i()}
}
