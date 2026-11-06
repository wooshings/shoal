package shoal

import rl "vendor:raylib"

// wire camera rendering into the app. add it AFTER DefaultPlugin — like the
// draw pipeline, it anchors its sets by name, and those anchors only resolve
// correctly once DefaultPlugin has declared them:
//
//	ecs.add_plugin(&app, ecs.DefaultPlugin)
//	ecs.add_plugin(&app, ecs.CameraPlugin)
//
// in frame order over "draw":
//
//	pre_draw (BeginDrawing + ClearBackground)
//	  -> camera_begin (BeginMode2D, see below; skipped with no camera)
//	  -> default (draw_sprite and everything added to the "draw" root)
//	  -> camera_end (EndMode2D)
//	  -> sets main() declared (before("post_draw") etc.) -> post_draw
//
// so systems registered on the "draw" root render WORLD space through the
// camera, while sets declared earlier in main() land after "camera_end" and
// render SCREEN space — automatic HUD/overlay separation without any extra
// component. a world with no Camera component skips the wrapping entirely
// and renders exactly as before
CameraPlugin :: proc(app: ^App) {
	init_system_set(app, "draw", "camera_begin", before("default"))
	init_system_set(app, "draw", "camera_end", after("default"))
	add_system(app, "camera_begin", begin_camera)
	add_system(app, "camera_end", end_camera)
}

// the raylib camera built this frame, driven by the Camera entity's transform.
// rebuilt every draw frame, so mutating the camera entity's Transform moves
// the view the same frame — no separate follow system to write
@(private)
camera_2d: rl.Camera2D

// whether camera_2d is valid and the world is currently wrapped in
// BeginMode2D — guards the paired EndMode2D so the plugin stays correct
// even when the begin half was skipped (no camera, or set order drifted)
@(private)
camera_2d_on: bool

// build the frame's rl.Camera2D from every Camera entity, false when none
// exists. the FIRST-registered camera acts (any extra ones just sit in the
// storage). the look-at is the camera entity's own Transform: its translation
// becomes the world point shown at the viewport center and its rotation
// becomes the roll around that point; that's why a camera entity needs a
// TransformComponent — like every sprite entity, a missing one is a fail-fast
// panic. zoom of zero falls back to 1, the same zero-means-default rule as
// SpriteComponent's tint
@(private)
build_camera_2d :: proc(world: ^World) -> (built: rl.Camera2D, ok: bool) {
	cameras := slice(world, Camera)
	if len(cameras) == 0 {
		return built, false
	}
	entity := slice_entity(world, Camera)[0]
	transform := get_component(world, entity, Transform)

	// the offset is the screen center, so transform.translation lands there —
	// the look-at point IS the center of the view. runtime screen size keeps
	// it correct through window resizes without touching the WindowComponent
	// (the window is open by the time anything locks in here)
	built = rl.Camera2D {
		offset   = {f32(rl.GetScreenWidth()) * 0.5, f32(rl.GetScreenHeight()) * 0.5},
		target   = transform.translation,
		rotation = transform.rotation,
		zoom     = 1.0,
	}
	if cameras[0].zoom != 0 {
		built.zoom = cameras[0].zoom
	}
	return built, true
}

// registered by CameraPlugin in the "camera_begin" set: opens 2d mode if the
// world holds a camera. guarded on rl.IsWindowReady so an ordering slip can't
// touch the matrix outside an open window, and camera_2d_on only flips on
// when the matching BeginMode2D actually ran
@(private)
begin_camera :: proc(world: ^World) {
	built, ok := build_camera_2d(world)
	if !ok || !rl.IsWindowReady() {
		return
	}
	camera_2d = built
	camera_2d_on = true
	rl.BeginMode2D(camera_2d)
}

// registered by CameraPlugin in the "camera_end" set: closes 2d mode iff it
// was opened this frame
@(private)
end_camera :: proc() {
	if camera_2d_on {
		camera_2d_on = false
		rl.EndMode2D()
	}
}

// the mouse position in camera world space: the screen cursor mapped through
// this frame's camera, so systems can turn a look-at + zoom view into world
// targets (click-to-move, picking). before "camera_begin", on frame one, or
// whenever no Camera component exists, there's nothing to map through and
// screen space IS world space — the raw cursor position is returned then
//
//	world_pos := ecs.cursor_world()
cursor_world :: proc() -> rl.Vector2 {
	if camera_2d_on {
		return rl.GetScreenToWorld2D(rl.GetMousePosition(), camera_2d)
	}
	return rl.GetMousePosition()
}
