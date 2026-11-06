package main

import ecs "../src"
import "core:math/rand"
import rl "vendor:raylib"

app: ecs.App

ball_count: int = 100000
Ball :: struct {
	radius: f32,
	speed:  f32,
}

main :: proc() {
	ecs.add_plugin(&app, ecs.DefaultPlugin)
	ecs.init_system_set(&app, "draw", "post_draw", ecs.after("default"))

	ecs.add_system(&app, "startup", setup_window)
	ecs.add_system(&app, "startup", spawn_balls)
	ecs.add_system(&app, "update", update_balls)
	ecs.add_system(&app, "post_draw", show_framerate)

	ecs.run(&app)
}

// startup system taking the world: the window lives in it, so adjusting the
// default WindowComponent is a world lookup now
setup_window :: proc(world: ^ecs.World) {
	window, _ := ecs.single(world, ecs.Window)
	window.background = rl.BLACK
}

// startup system taking the world: spawn_entity wants it, and the balls'
// components live inside it, no global storage to declare
spawn_balls :: proc(world: ^ecs.World) {
	// load once, share everywhere: load_sprite caches by path, so every ball
	// references the same texture id. distinct texture ids defeat raylib's
	// renderer batching — one draw call per batch instead of one per sprite
	sprite := ecs.load_sprite("assets/gregory.png")
	sprite.scale = {0.1, 0.1}
	sprite.tint = rl.PURPLE

	for i in 0 ..< ball_count {
		ball := ecs.spawn_entity(world)
		ecs.add_component(world, ball, Ball{5, rand.float32_range(4, 6)})
		ecs.add_component(world, ball, ecs.Transform{{400, 300}, rand.float32_range(0, 360)})
		ecs.add_component(world, ball, sprite)
	}
}

update_balls :: proc(world: ^ecs.World) {
	window, _ := ecs.single(world, ecs.Window)

	balls := ecs.slice(world, Ball)
	entities := ecs.slice_entity(world, Ball)
	for ball, i in balls {
		transform := ecs.get_component(world, entities[i], ecs.Transform)
		pos := transform.translation

		if pos.x <= 0 || pos.x >= f32(window.width) || pos.y <= 0 || pos.y >= f32(window.height) {
			transform.rotation -= 180
		}
		dir := rl.Vector2Rotate(rl.Vector2{0, ball.speed}, transform.rotation)

		transform.translation += dir
	}
}

draw_balls :: proc(world: ^ecs.World) {
	balls := ecs.slice(world, Ball)
	entities := ecs.slice_entity(world, Ball)
	for ball, i in balls {
		transform := ecs.get_component(world, entities[i], ecs.Transform)
		rl.DrawCircle(
			i32(transform.translation.x),
			i32(transform.translation.y),
			ball.radius,
			rl.PURPLE,
		)
	}
}

show_framerate :: proc() {
	rl.DrawFPS(0, 0)
	rl.DrawText("100000 fih", 0, 24, 24, rl.WHITE)
}
