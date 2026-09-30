package shoal

import "core:text/table"
import rl "vendor:raylib"

STARTUP := 0
UPDATE := 1
DRAW := 2

App :: struct {
	startup_systems: [dynamic]proc(),
	update_systems:  [dynamic]proc(),
	draw_systems:    [dynamic]proc(),
	plugins:         [dynamic]proc(app: ^App),
	entities:        [dynamic]Entity,
}

add_system :: proc(app: ^App, schedule: int, system: proc()) {
	switch schedule {
	case STARTUP:
		append(&app.startup_systems, system)
	case UPDATE:
		append(&app.update_systems, system)
	case DRAW:
		append(&app.draw_systems, system)
	}
}

add_plugin :: proc(app: ^App, plugin: proc(app: ^App)) {
	append(&app.plugins, plugin)
}


run :: proc(app: ^App) {
	rl.InitWindow(800, 600, "shoal window")
	defer rl.CloseWindow()

	for p in app.plugins {
		p(app)
	}

	for i in app.startup_systems {i()}
	for !rl.WindowShouldClose() {
		for i in app.update_systems {i()}
		rl.BeginDrawing()
		for i in app.draw_systems {i()}
		rl.EndDrawing()
	}
}
