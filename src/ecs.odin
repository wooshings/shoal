package shoal

import "core:strings"
import rl "vendor:raylib"

STARTUP :: 0
UPDATE :: 1
DRAW :: 2

App :: struct {
	systems:  map[int][dynamic]proc(),
	plugins:  [dynamic]proc(app: ^App),
	entities: [dynamic]Entity,
}

// add a new system to the app that will run based on the provided schedule
add_system :: proc(app: ^App, schedule: int, system: proc()) {
	append(&app.systems[schedule], system)
}

// add a new plugin to the app. a modular way to add new functionality from beyond the main procedure
add_plugin :: proc(app: ^App, plugin: proc(app: ^App)) {
	append(&app.plugins, plugin)
}

// run the app
run :: proc(app: ^App) {
	for p in app.plugins {
		p(app)
	}
	for i in app.systems[STARTUP] {i()}

	_, window := single(&Window)
	rl.InitWindow(window.width, window.height, strings.clone_to_cstring(window.title))
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)
	for !rl.WindowShouldClose() {
		rl.ClearBackground(window.background)
		for i in app.systems[UPDATE] {i()}
		rl.BeginDrawing()
		for i in app.systems[DRAW] {i()}
		rl.EndDrawing()
	}
}
