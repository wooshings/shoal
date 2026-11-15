package shoal

import rl "vendor:raylib"

CameraPlugin :: proc(app: ^App) {
	init_system_set(app, "draw", "camera_begin", before("default"))
	init_system_set(app, "draw", "camera_end", after("default"))
	add_system(app, "camera_begin", begin_camera)
	add_system(app, "camera_end", end_camera)
}

@(private)
camera_2d: rl.Camera2D

@(private)
camera_2d_on: bool

build_camera_2d :: proc(world: ^World) -> (built: rl.Camera2D, ok: bool) {
	cameras := slice(world, Camera)
	if len(cameras) == 0 {
		return built, false
	}
	entity := slice_entity(world, Camera)[0]
	transform := get_component(world, entity, Transform)

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

@(private)
end_camera :: proc() {
	if camera_2d_on {
		camera_2d_on = false
		rl.EndMode2D()
	}
}

cursor_world :: proc() -> rl.Vector2 {
	if camera_2d_on {
		return rl.GetScreenToWorld2D(rl.GetMousePosition(), camera_2d)
	}
	return rl.GetMousePosition()
}
