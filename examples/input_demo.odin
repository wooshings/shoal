package main

import ecs "../src"
import input "../plugins/input"
import rl "vendor:raylib"

app: ecs.App

main :: proc() {
	ecs.add_plugin(&app, ecs.DefaultPlugin)
	ecs.add_plugin(&app, input.InputPlugin)

	// action mapping: "jump" bound to space, rebindable at runtime
	input.bind("jump", input.SPACE)

	ecs.add_system(&app, "update", show_state)
	ecs.run(&app)
}

show_state :: proc(world: ^ecs.World) {
	if input.action_pressed("jump") {
		rl.TraceLog(.INFO, "jump pressed")
	}
	// buffered input: a press up to 0.1s ago still counts
	if input.consume_buffered("jump", 0.1) {
		rl.TraceLog(.INFO, "buffered jump consumed")
	}
	if input.mouse_pressed(input.MB_LEFT) {
		rl.TraceLog(.INFO, "left click at %v", input.mouse_position())
	}
	_ = world
}