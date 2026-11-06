package main

// camera demo: CameraPlugin renders the "draw" root through a camera whose
// look-at is its own entity's TransformComponent. WASD moves the look-at,
// the scroll wheel zooms, right-click teleports the look-at to the world
// point under the cursor (via cursor_world), and the HUD set renders in
// screen space after the camera ends — same demo data, two coordinate
// spaces. no assets needed
//
//	odin run examples/camera_demo.odin -file -collection:raylib=<vendor raylib path>

import ecs "../src"
import "core:fmt"
import rl "vendor:raylib"

app: ecs.App

camera_entity: ecs.Entity
camera_zoom: f32 = 1.0

main :: proc() {
	// the camera plugin must come after DefaultPlugin: it anchors its
	// begin/end sets around draw's "default" set by name
	ecs.add_plugin(&app, ecs.DefaultPlugin)
	ecs.add_plugin(&app, ecs.CameraPlugin)

	ecs.add_system(&app, "startup", spawn_camera)
	ecs.add_system(&app, "update", move_camera)
	ecs.add_system(&app, "draw", draw_world) // through the camera: "draw"'s
	// default set sits between camera_begin and camera_end

	// HUD: a set declared before("post_draw") lands after camera_end, so it
	// draws in plain screen space, unmoved by pan/zoom/roll — no extra
	// plugin needed
	ecs.init_system_set(&app, "draw", "hud", ecs.before("post_draw"))
	ecs.add_system(&app, "hud", draw_hud)

	ecs.run(&app)
}

// startup system taking the world: the camera entity is spawned here so the
// Camera component and its Transform-look-at live in the same world the
// systems read each frame. a camera entity without a Transform is a panic,
// same rule as every sprite entity
spawn_camera :: proc(world: ^ecs.World) {
	camera_entity = ecs.spawn_entity(world)
	ecs.add_component(world, camera_entity, ecs.Camera{})

	// zeroed Camera{zoom = 0} means default zoom 1.0
	ecs.add_component(world, camera_entity, ecs.Transform{translation = {0, 0}})
}

// move the look-at with WASD, zoom with the wheel, right-click to look at
// the world point under the mouse. the camera moves by writing its entity's
// Transform — nothing hooky, it's just an entity
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
		// raylib forbids zoom <= 0; writing it back through the component
		// keeps the build sane — zero Camera.zoom reads back as 1.0 anyway
		ecs.get_component(world, camera_entity, ecs.Camera).zoom = camera_zoom
	}

	if rl.IsMouseButtonDown(rl.MouseButton.RIGHT) {
		// cursor_world turns the screen cursor into a world point through
		// this frame's camera, so the view can look at whatever you clicked
		transform.translation = ecs.cursor_world()
	}
}

// everything registered on the "draw" root lands in draw's default set,
// between camera_begin and camera_end: world space, transformed by the
// camera. offsets are world coordinates, the look-at lands at screen center
draw_world :: proc(world: ^ecs.World) {
	// a marker where the look-at is — the camera's own entity's position
	transform := ecs.get_component(world, camera_entity, ecs.Transform)
	rl.DrawCircleLinesV(transform.translation, 12, rl.YELLOW)

	// world-anchored text: at zoom 2 it's drawn twice as big, so text doubles
	// as a zoom indicator
	rl.DrawText("world space: (0, 0)", 10, 10, 20, rl.WHITE)
	rl.DrawText("this text lives at (10, 10)", 10, 40, 20, rl.GREEN)

	// the world mouse position as raylib computes it this frame
	mouse := ecs.cursor_world()
	rl.DrawCircleV(mouse, 5, rl.SKYBLUE)
	// dynamic text: fill a stack buffer each frame (DrawText copies it), no
	// per-frame allocation
	mouse_buf: [64]u8
	pos_text := fmt.tprintf("cursor world: ({:.1}, {:.1})", mouse.x, mouse.y)
	n := min(len(pos_text), len(mouse_buf) - 1)
	copy(mouse_buf[:n], pos_text[:n])
	mouse_buf[n] = 0
	rl.DrawText(cstring(&mouse_buf[0]), 10, 70, 20, rl.SKYBLUE)
}

// the HUD set is declared before("post_draw"), which puts it after
// camera_end: plain screen space, unmoved by pan/zoom/roll. same draw
// schedule, no extra plugin
draw_hud :: proc() {
	rl.DrawRectangle(0, 0, 210, 108, rl.Color{0, 0, 0, 140})
	rl.DrawText("WASD: move look-at", 10, 10, 20, rl.WHITE)
	rl.DrawText("wheel: zoom", 10, 40, 20, rl.WHITE)
	rl.DrawText("RMB: look at cursor", 10, 70, 20, rl.WHITE)
}
