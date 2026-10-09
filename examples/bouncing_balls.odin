package main

import "core:fmt"
import "core:math/rand"
import "core:strconv"
import "core:strings"
import ecs "shoal/src"
import rl "vendor:raylib"

app: ecs.App

ball_count: int = 1000
BallComponent :: struct {
	radius: f32,
	speed:  f32,
}
Ball: ecs.Storage(BallComponent)

main :: proc() {
	ecs.add_plugin(&app, ecs.DefaultPlugin)
	ecs.add_system(&app, ecs.STARTUP, setup_window)
	ecs.add_system(&app, ecs.STARTUP, spawn_balls)
	ecs.add_system(&app, ecs.UPDATE, update_balls)
	ecs.add_system(&app, ecs.DRAW, draw_balls)
	ecs.add_system(&app, ecs.DRAW, show_framerate)
	ecs.run(&app)
}

setup_window :: proc() {
	_, window := ecs.single(&ecs.Window)
	window.background = rl.BLACK
}

spawn_balls :: proc() {
	for i in 0 ..< ball_count {
		ball := ecs.spawn_entity(&app)
		ecs.add_component(
			ball,
			&Ball,
			BallComponent{radius = 10, speed = rand.float32_range(4, 6)},
		)
		ecs.add_component(
			ball,
			&ecs.Transform,
			ecs.TransformComponent {
				translation = {400, 300},
				rotation = rand.float32_range(0, 360),
			},
		)
	}
}

update_balls :: proc() {
	_, window := ecs.single(&ecs.Window)

	for entity, ball in ecs.slice(&Ball) {
		transform := ecs.get_component(entity, &ecs.Transform)
		pos := transform.translation

		if pos.x <= 0 || pos.x >= f32(window.width) || pos.y <= 0 || pos.y >= f32(window.height) {
			transform.rotation -= 180
		}
		dir := rl.Vector2Rotate(rl.Vector2{0, ball.speed}, transform.rotation)

		transform.translation += dir
		fmt.println(transform.rotation)
	}
}

draw_balls :: proc() {
	for entity, ball in ecs.slice(&Ball) {
		transform := ecs.get_component(entity, &ecs.Transform)
		rl.DrawCircle(
			i32(transform.translation.x),
			i32(transform.translation.y),
			ball.radius,
			rl.PURPLE,
		)
	}
}

show_framerate :: proc() {
	buf: [19]byte
	framerate := strconv.write_int(buf[:], i64(1 / rl.GetFrameTime()), 10)
	rl.DrawText(strings.clone_to_cstring(framerate), 0, 0, 24, rl.WHITE)
}
