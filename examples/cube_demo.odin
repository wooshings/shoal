package main

import ecs "../src"
import rl "vendor:raylib"

app: ecs.App

main :: proc() {
	ecs.window(&app, ecs.Window{width = 800, height = 600, title = "cube demo"})

	ecs.add_plugin(&app, ecs.Default3DPlugin)

	ecs.add_system(&app, "startup", setup)
	ecs.add_system(&app, "update", spin)

	ecs.run(&app)
}

setup :: proc(world: ^ecs.World) {
	window, _ := ecs.single(world, ecs.Window)
	window.background = rl.SKYBLUE

	// a camera
	cam := ecs.spawn_entity(world)
	ecs.add_component(world, cam, ecs.Transform3D{{0, 5, 10}, {}, {1, 1, 1}})
	ecs.add_component(world, cam, ecs.Camera3D{{0, 0, 0}, {0, 1, 0}, 45, rl.CameraProjection.PERSPECTIVE})

	// a spinning cube
	cube := ecs.spawn_entity(world)
	ecs.add_component(world, cube, ecs.Transform3D{{0, 0, 0}, {}, {1, 1, 1}})
	ecs.add_component(world, cube, ecs.gen_model_cube(1, 1, 1))

	// a floor
	floor := ecs.spawn_entity(world)
	ecs.add_component(world, floor, ecs.Transform3D{{0, -1, 0}, {}, {10, 0.1, 10}})
	ecs.add_component(world, floor, ecs.gen_model_cube(1, 1, 1))
}

spin :: proc(world: ^ecs.World) {
	cubes := ecs.slice(world, ecs.Model)
	entities := ecs.slice_entity(world, ecs.Model)
	for _, i in cubes {
		t := ecs.get_component(world, entities[i], ecs.Transform3D)
		t.rotation.y += rl.GetFrameTime()
	}
}