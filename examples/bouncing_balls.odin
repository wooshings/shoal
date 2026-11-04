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

	// declare child schedules (system sets) under the root schedules
	ecs.init_system_set(&app, "startup", "window")
	ecs.init_system_set(&app, "startup", "spawn")
	ecs.init_system_set(&app, "update", "physics")
	ecs.init_system_set(&app, "draw", "render")
	ecs.init_system_set(&app, "draw", "hud")

	// register systems add_system-style: the child schedule name is enough —
	// "window"/"spawn" resolve to their "startup" parent, "physics" to
	// "update", "render"/"hud" to "draw"
	ecs.add_system(&app, "window", setup_window)
	ecs.add_system(&app, "spawn", spawn_balls)
	ecs.add_system(&app, "physics", update_balls)
	ecs.add_system(&app, "render", draw_balls)
	ecs.add_system(&app, "hud", show_framerate)

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
	for i in 0 ..< ball_count {
		ball := ecs.spawn_entity(world)
		ecs.add_component(world, ball, BallComponent{5, rand.float32_range(4, 6)})
		ecs.add_component(
			world,
			ball,
			ecs.Transform{{400, 300}, rand.float32_range(0, 360)},
		)
	}
}

update_balls :: proc(world: ^ecs.World) {
	window, _ := ecs.single(world, ecs.Window)

	balls := ecs.slice(world, BallComponent)
	entities := ecs.slice_entity(world, BallComponent)
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
	balls := ecs.slice(world, BallComponent)
	entities := ecs.slice_entity(world, BallComponent)
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
	fps_buf: [19]byte
	framerate := strconv.write_int(fps_buf[:], i64(1 / rl.GetFrameTime()), 10)
	rl.DrawText(strings.clone_to_cstring(framerate), 0, 0, 24, rl.WHITE)
	rl.DrawText("   fps", 0, 24, 24, rl.WHITE)
	rl.DrawText("10000 balls", 0, 24, 24, rl.WHITE)
}
