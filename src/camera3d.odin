package shoal

import rl "vendor:raylib"

Camera3DPlugin :: proc(app: ^App) {
	init_system_set(app, "draw", "camera_3d_begin", before("default"))
	init_system_set(app, "draw", "camera_3d_end", after("default"))
	add_system(app, "camera_3d_begin", begin_camera_3d)
	add_system(app, "camera_3d_end", end_camera_3d)
}

@(private)
camera_3d: rl.Camera3D

@(private)
camera_3d_on: bool

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

cursor_ray :: proc() -> rl.Ray {
	if camera_3d_on {
		return rl.GetScreenToWorldRay(rl.GetMousePosition(), camera_3d)
	}
	return rl.Ray{}
}
