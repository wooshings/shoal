package main

import "core:math/rand"
import "core:strconv"
import "core:strings"
import ecs "../src"
import rl "vendor:raylib"

app: ecs.App

ball_count: int = 10000
BallComponent :: struct {
	radius: f32,
	speed:  f32,
}

main :: proc() {
	ecs.add_plugin(&app, ecs.DefaultPlugin)
	ecs.add_system(&app, ecs.STARTUP, setup_window)
	ecs.add_system(&app, ecs.STARTUP, spawn_balls)
	ecs.add_system(&app, ecs.UPDATE, update_balls)
	ecs.add_system(&app, ecs.DRAW, draw_balls)
	ecs.add_system(&app, ecs.DRAW, show_framerate)
	ecs.run(&app)
}

// STARTUP system taking the world: the window lives in it, so adjusting the
// default WindowComponent is a world lookup now
setup_window :: proc(world: ^ecs.World) {
	window, _ := ecs.single(world, ecs.WindowComponent)
	window.background = rl.BLACK
}

// STARTUP system taking the world: spawn_entity wants it, and the balls'
// components live inside it, no global storage to declare
spawn_balls :: proc(world: ^ecs.World) {
	for i in 0 ..< ball_count {
		ball := ecs.spawn_entity(world)
		ecs.add_component(world, ball, BallComponent{radius = 5, speed = rand.float32_range(4, 6)})
		ecs.add_component(
			world,
			ball,
			ecs.TransformComponent {
				translation = {400, 300},
				rotation = rand.float32_range(0, 360),
			},
		)
	}
}

update_balls :: proc(world: ^ecs.World) {
	window, _ := ecs.single(world, ecs.WindowComponent)

	balls := ecs.slice(world, BallComponent)
	entities := ecs.slice_entity(world, BallComponent)
	for ball, i in balls {
		transform := ecs.get_component(world, entities[i], ecs.TransformComponent)
		pos := transform.translation

		if pos.x <= 0 || pos.x >= f32(window.width) || pos.y <= 0 || pos.y >= f32(window.height) {
			transform.rotation -= 180
		}
		dir := rl.Vector2Rotate(rl.Vector2{0, ball.speed}, transform.rotation)

		transform.translation += dir
	}
}

draw_balls :: proc(world: ^ecs.World) {
	balls := ecs.slice(world, BallComponent)
	entities := ecs.slice_entity(world, BallComponent)
	for ball, i in balls {
		transform := ecs.get_component(world, entities[i], ecs.TransformComponent)
		rl.DrawCircle(
			i32(transform.translation.x),
			i32(transform.translation.y),
			ball.radius,
			rl.PURPLE,
		)
	}
}

show_framerate :: proc() {
	fps_buf: [19]byte
	framerate := strconv.write_int(fps_buf[:], i64(1 / rl.GetFrameTime()), 10)
	rl.DrawText(strings.clone_to_cstring(framerate), 0, 0, 24, rl.WHITE)
	rl.DrawText("   fps", 0, 24, 24, rl.WHITE)
	rl.DrawText("10000 balls", 0, 24, 24, rl.WHITE)
}
