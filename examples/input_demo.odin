package main

import ecs "../src"
import input "../plugins/input"
import "core:fmt"

main :: proc() {
	app: ecs.App
	ecs.add_plugin(&app, ecs.DefaultPlugin)

	input.bind("jump", input.SPACE)

	ecs.add_system(&app, "update", show_state)
	ecs.run(&app)
}

show_state :: proc(world: ^ecs.World) {
	if input.is_pressed(input.SPACE) {
		fmt.println("jump key triggered")
	}
	if input.action_pressed("jump") {
		fmt.println("jump action triggered")
	}

	if input.consume_buffered("jump", 0.1) {
		fmt.println("jump action consumed")
	}
	if input.mouse_pressed(input.MB_LEFT) {
		fmt.println("left click at %v", input.mouse_position())
	}
	_ = world
}
