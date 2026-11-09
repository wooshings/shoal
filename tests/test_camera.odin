package tests

// tests for the CameraPlugin draw pipeline and the camera 2d build. same
// shape as the DefaultPlugin pipeline tests in test_scheduling.odin:
// registration layout only — the begin/end systems are never run here, that
// would need a window. the build proc is pure enough to test against a bare
// world. run with:
//
//	odin test tests -collection:raylib=<odin vendor raylib path>

import ecs "../src"
import "core:testing"
import rl "vendor:raylib"

// --- the CameraPlugin draw pipeline ---

@(test)
camera_plugin_pipeline_with_declared_user_sets :: proc(t: ^testing.T) {
	app: ecs.App
	// main() runs first in the real order: user sets declared, then
	// DefaultPlugin, then CameraPlugin (the documented required order)
	ecs.init_system_set(&app, "draw", "render")
	ecs.init_system_set(&app, "draw", "hud")
	ecs.add_system(&app, "render", p_user)
	ecs.add_system(&app, "hud", p_root)
	ecs.DefaultPlugin(&app)
	ecs.CameraPlugin(&app)

	expect_set_order(t, &app, "draw",
		[]string{"pre_draw", "camera_begin", "default", "camera_end", "render", "hud", "post_draw"})
	testing.expect(t, len(ecs.get_system(&app, "draw", "camera_begin")) == 1, "camera_begin registered")
	testing.expect(t, len(ecs.get_system(&app, "draw", "camera_end")) == 1, "camera_end registered")
}

@(test)
camera_plugin_pipeline_no_user_sets :: proc(t: ^testing.T) {
	app: ecs.App
	ecs.DefaultPlugin(&app)
	ecs.CameraPlugin(&app)

	expect_set_order(t, &app, "draw",
		[]string{"pre_draw", "camera_begin", "default", "camera_end", "post_draw"})
}

@(test)
camera_plugin_requires_default_plugin_first :: proc(t: ^testing.T) {
	app: ecs.App
	// CameraPlugin alone still declares its sets; anchors fall back to front/back
	ecs.CameraPlugin(&app)
	// at least the sets exist
	testing.expect(t, len(ecs.get_system(&app, "draw", "camera_begin")) == 1, "camera_begin registered")
	testing.expect(t, len(ecs.get_system(&app, "draw", "camera_end")) == 1, "camera_end registered")
}

// --- camera 2d build (pure, no window) ---

@(test)
build_camera_2d_absent_returns_false :: proc(t: ^testing.T) {
	world: ecs.World
	_, ok := ecs.build_camera_2d(&world)
	testing.expect(t, !ok, "no camera component -> not built")
}

@(test)
build_camera_2d_with_camera_and_transform :: proc(t: ^testing.T) {
	world: ecs.World
	entity := ecs.spawn_entity(&world)
	ecs.add_component(&world, entity, ecs.Camera{zoom = 2.0})
	ecs.add_component(&world, entity, ecs.Transform{translation = {10, 20}, rotation = 5})

	cam, ok := ecs.build_camera_2d(&world)
	testing.expect(t, ok, "built with camera + transform")
	testing.expect(t, cam.target == (rl.Vector2{10, 20}), "target from transform")
	testing.expect(t, cam.rotation == 5, "rotation from transform")
	testing.expect(t, cam.zoom == 2.0, "zoom from camera")
}

@(test)
build_camera_2d_zero_zoom_defaults_to_one :: proc(t: ^testing.T) {
	world: ecs.World
	entity := ecs.spawn_entity(&world)
	ecs.add_component(&world, entity, ecs.Camera{zoom = 0})
	ecs.add_component(&world, entity, ecs.Transform{translation = {0, 0}, rotation = 0})

	cam, ok := ecs.build_camera_2d(&world)
	testing.expect(t, ok, "built")
	testing.expect(t, cam.zoom == 1.0, "zero zoom -> 1.0")
}

@(test)
camera_absent_writes_screen_space :: proc(t: ^testing.T) {
	// registration shape only: no camera component means the camera_begin set
	// is a no-op at run time, so draw stays in screen space. here we just
	// confirm the plugin registers without a camera entity present.
	app: ecs.App
	ecs.DefaultPlugin(&app)
	ecs.CameraPlugin(&app)
	testing.expect(t, len(ecs.get_schedule_set_order(&app, "draw")) > 0, "draw pipeline declared")
}