package shoal

import ui "../ui"
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

// run the app
run :: proc(app: ^App, entity_limit: int = 1000) {
	sparse_entity_limit = entity_limit

	for p in app.plugins {
		p(app)
	}
	for i in app.systems[STARTUP] {i()}

	window, _ := single(&Window)
	rl.InitWindow(window.width, window.height, strings.clone_to_cstring(window.title))
	ui.ui_ctx = ui.init_scope()
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)
	for !rl.WindowShouldClose() {
		defer free_all(context.temp_allocator)
		for i in app.systems[UPDATE] {i()}
		rl.BeginDrawing(); defer rl.EndDrawing()
		ui.begin_scope()
		rl.ClearBackground(window.background)
		for i in app.systems[DRAW] {i()}
	}
}
