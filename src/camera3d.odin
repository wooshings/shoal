package shoal

import rl "vendor:raylib"

// wire 3d camera rendering into the app. add it AFTER DefaultPlugin — like
// the 2d camera plugin, it anchors its sets by name, and those anchors only
// resolve correctly once DefaultPlugin has declared them:
//
//	ecs.add_plugin(&app, ecs.DefaultPlugin)
//	ecs.add_plugin(&app, ecs.Camera3DPlugin)
//
// in frame order over "draw":
//
//	pre_draw (BeginDrawing + ClearBackground)
//	  -> camera_3d_begin (BeginMode3D, skipped with no Camera3D)
//	  -> default (draw_model and everything added to the "draw" root)
//	  -> camera_3d_end (EndMode3D)
//	  -> sets main() declared (before("post_draw") etc.) -> post_draw
//
// so systems registered on the "draw" root render WORLD space through the
// 3d camera, while sets declared earlier in main() land after
// "camera_3d_end" and render SCREEN space. a world with no Camera3D
// component skips the wrapping entirely. 2d and 3d camera plugins both wrap
// the same "default" set, so use one or the other, not both
Camera3DPlugin :: proc(app: ^App) {
	init_system_set(app, "draw", "camera_3d_begin", before("default"))
	init_system_set(app, "draw", "camera_3d_end", after("default"))
	add_system(app, "camera_3d_begin", begin_camera_3d)
	add_system(app, "camera_3d_end", end_camera_3d)
}

// the raylib camera built this frame, driven by the Camera3D entity's
// transform. rebuilt every draw frame, so mutating the camera entity's
// Transform3D moves the view the same frame
@(private)
camera_3d: rl.Camera3D

// whether camera_3d is valid and the world is currently wrapped in
// BeginMode3D — guards the paired EndMode3D
@(private)
camera_3d_on: bool

// build the frame's rl.Camera3D from every Camera3D entity, false when none
// exists. the FIRST-registered camera acts. position comes from the
// entity's Transform3D (fail-fast panic if it's missing, like the 2d
// camera). zero-valued fields fall back to defaults: target one unit
// forward along +Z, up {0,1,0}, fovy 45, projection PERSPECTIVE
build_camera_3d :: proc(world: ^World) -> (built: rl.Camera3D, ok: bool) {
	cameras := slice(world, Camera3D)
	if len(cameras) == 0 {
		return built, false
	}
	entity := slice_entity(world, Camera3D)[0]
	transform := get_component(world, entity, Transform3D)

	built.position = transform.translation
	if cameras[0].target == (rl.Vector3{}) {
		built.target = transform.translation + rl.Vector3{0, 0, 1}
	} else {
		built.target = cameras[0].target
	}
	if cameras[0].up == (rl.Vector3{}) {
		built.up = rl.Vector3{0, 1, 0}
	} else {
		built.up = cameras[0].up
	}
	if cameras[0].fovy == 0 {
		built.fovy = 45
	} else {
		built.fovy = cameras[0].fovy
	}
	built.projection = cameras[0].projection
	return built, true
}

@(private)
begin_camera_3d :: proc(world: ^World) {
	built, ok := build_camera_3d(world)
	if !ok || !rl.IsWindowReady() {
		return
	}
	camera_3d = built
	camera_3d_on = true
	rl.BeginMode3D(camera_3d)
}

@(private)
end_camera_3d :: proc() {
	if camera_3d_on {
		camera_3d_on = false
		rl.EndMode3D()
	}
}

// the mouse as a picking ray through this frame's 3d camera: origin and
// direction in world space. before "camera_3d_begin", on frame one, or
// whenever no Camera3D component exists, returns a zero ray (origin and
// direction both {0,0,0}) — there's nothing to unproject through
cursor_ray :: proc() -> rl.Ray {
	if camera_3d_on {
		return rl.GetScreenToWorldRay(rl.GetMousePosition(), camera_3d)
	}
	return rl.Ray{}
}