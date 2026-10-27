package shoal

import "core:strings"
import "core:thread"
import ml "vendor:microui"
import rl "vendor:raylib"

update_pool: thread.Pool

@(private)
sparse_entity_limit: int

get_entity_limit :: proc() -> int {
	return sparse_entity_limit
}

App :: struct {
	systems:  map[int][dynamic]proc(),
	plugins:  [dynamic]proc(app: ^App),
	entities: [dynamic]Entity,
}

// add a new system to the app that will run based on the provided schedule
add_system :: proc(app: ^App, schedule: int, system: proc()) {
	if _, ok := app.systems[schedule]; !ok {
		app.systems[schedule] = [dynamic]proc(){}
	}
	append(&app.systems[schedule], system)
}

// add a new plugin to the app. a modular way to add new functionality from beyond the main procedure
add_plugin :: proc(app: ^App, plugin: proc(app: ^App)) {
	append(&app.plugins, plugin)
}

get_system :: proc(app: ^App, schedule: int) -> [dynamic]proc() {
	if systems, ok := app.systems[schedule]; ok && len(systems) > 0 {
		return systems
	}
	return [dynamic]proc(){}
}

// run the app
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
