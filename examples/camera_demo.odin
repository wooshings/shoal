package main

import ecs "../src"
import "core:fmt"
import rl "vendor:raylib"

camera_entity: ecs.Entity
camera_zoom: f32 = 1.0

main :: proc() {
	app: ecs.App

	ecs.add_plugin(&app, ecs.DefaultPlugin)
	ecs.add_plugin(&app, ecs.CameraPlugin)

	ecs.add_system(&app, "startup", spawn_camera)
	ecs.add_system(&app, "update", move_camera)
	ecs.add_system(&app, "draw", draw_world)

	ecs.init_system_set(&app, "draw", "hud", ecs.before("post_draw"))
	ecs.add_system(&app, "hud", draw_hud)

	ecs.run(&app)
}

spawn_camera :: proc(world: ^ecs.World) {
	camera_entity = ecs.spawn_entity(world)
	ecs.add_component(world, camera_entity, ecs.Camera{})

	ecs.add_component(world, camera_entity, ecs.Transform{translation = {0, 0}})
}

move_camera :: proc(world: ^ecs.World) {
	dt := rl.GetFrameTime()
	speed := f32(300) * dt / camera_zoom

	transform := ecs.get_component(world, camera_entity, ecs.Transform)

	if rl.IsKeyDown(rl.KeyboardKey.W) {transform.translation.y -= speed}
	if rl.IsKeyDown(rl.KeyboardKey.S) {transform.translation.y += speed}
	if rl.IsKeyDown(rl.KeyboardKey.A) {transform.translation.x -= speed}
	if rl.IsKeyDown(rl.KeyboardKey.D) {transform.translation.x += speed}

	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {
		camera_zoom = max(min(camera_zoom + wheel * f32(0.25), 4.0), 0.25)

		ecs.get_component(world, camera_entity, ecs.Camera).zoom = camera_zoom
	}

	if rl.IsMouseButtonDown(rl.MouseButton.RIGHT) {

		transform.translation = ecs.cursor_world()
	}
}

draw_world :: proc(world: ^ecs.World) {

	transform := ecs.get_component(world, camera_entity, ecs.Transform)
	rl.DrawCircleLinesV(transform.translation, 12, rl.YELLOW)

	rl.DrawText("world space: (0, 0)", 10, 10, 20, rl.WHITE)
	rl.DrawText("this text lives at (10, 10)", 10, 40, 20, rl.GREEN)

	mouse := ecs.cursor_world()
	rl.DrawCircleV(mouse, 5, rl.SKYBLUE)

	mouse_buf: [64]u8
	pos_text := fmt.tprintf("cursor world: ({:.1}, {:.1})", mouse.x, mouse.y)
	n := min(len(pos_text), len(mouse_buf) - 1)
	copy(mouse_buf[:n], pos_text[:n])
	mouse_buf[n] = 0
	rl.DrawText(cstring(&mouse_buf[0]), 10, 70, 20, rl.SKYBLUE)
}

draw_hud :: proc() {
	rl.DrawRectangle(0, 0, 210, 108, rl.Color{0, 0, 0, 140})
	rl.DrawText("WASD: move look-at", 10, 10, 20, rl.WHITE)
	rl.DrawText("wheel: zoom", 10, 40, 20, rl.WHITE)
	rl.DrawText("RMB: look at cursor", 10, 70, 20, rl.WHITE)
}
