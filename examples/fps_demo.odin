package main

import ecs "../src"
import rl "vendor:raylib"
import "core:math"

app: ecs.App

Player :: struct {
	yaw:       f32,
	pitch:     f32,
	vel:       rl.Vector3,
	grounded:  bool,
	speed:     f32,
	sensitivity: f32,
	eye_height: f32,
}

main :: proc() {
	ecs.window(&app, ecs.Window{width = 1280, height = 720, title = "fps demo"})
	ecs.add_plugin(&app, ecs.Default3DPlugin)

	ecs.add_system(&app, "startup", setup)
	ecs.add_system(&app, "update", update)

	ecs.run(&app)
}

setup :: proc(world: ^ecs.World) {
	window, _ := ecs.single(world, ecs.Window)
	window.background = rl.SKYBLUE

	player := ecs.spawn_entity(world)
	ecs.add_component(world, player, ecs.Transform3D{translation = {0, 1.6, 0}})
	ecs.add_component(world, player, ecs.Camera3D{target = {0, 1.6, 1}, up = {0, 1, 0}, fovy = 75, projection = rl.CameraProjection.PERSPECTIVE})
	ecs.add_component(world, player, Player{speed = 5, sensitivity = 0.003, eye_height = 1.6})

	floor := ecs.spawn_entity(world)
	ecs.add_component(world, floor, ecs.Transform3D{translation = {0, -0.5, 0}, scale = {30, 1, 30}})
	ecs.add_component(world, floor, ecs.gen_model_cube(1, 1, 1))
	ecs.add_component(world, floor, ecs.collider3d(30, 1, 30))

	for i in 0 ..< 4 {
		box := ecs.spawn_entity(world)
		x := f32(i*4 - 6)
		ecs.add_component(world, box, ecs.Transform3D{translation = {x, 0.5, 0}, scale = {1.5, 1, 1.5}})
		ecs.add_component(world, box, ecs.gen_model_cube(1, 1, 1))
		ecs.add_component(world, box, ecs.collider3d(1.5, 1, 1.5))
	}

	tall := ecs.spawn_entity(world)
	ecs.add_component(world, tall, ecs.Transform3D{translation = {5, 1, 4}, scale = {2, 2, 2}})
	ecs.add_component(world, tall, ecs.gen_model_cube(1, 1, 1))
	ecs.add_component(world, tall, ecs.collider3d(2, 2, 2))

	rl.DisableCursor()
}

player_aabb :: proc(eye: rl.Vector3, eye_height: f32) -> (min, max: rl.Vector3) {
	bottom := eye.y - eye_height
	top := eye.y + 0.2
	center := rl.Vector3{eye.x, (bottom + top) * 0.5, eye.z}
	half := rl.Vector3{0.3, (top - bottom) * 0.5, 0.3}
	min = center - half
	max = center + half
	return
}

collides :: proc(world: ^ecs.World, eye: rl.Vector3, eye_height: f32) -> bool {
	pmin, pmax := player_aabb(eye, eye_height)

	models := ecs.slice(world, ecs.Model)
	entities := ecs.slice_entity(world, ecs.Model)
	for _, i in models {
		t := ecs.get_component(world, entities[i], ecs.Transform3D)

		size := t.scale
		if c, ok := ecs.try_get_component(world, entities[i], ecs.Collider3D); ok {
			if c.size.x > 0 && c.size.y > 0 && c.size.z > 0 {
				size = c.size
			} else if c.width > 0 {
				size = rl.Vector3{c.width, c.height, c.length}
			}
			if !c.solid { continue }
		}

		half := size * 0.5
		bmin := t.translation - half
		bmax := t.translation + half

		if pmax.x > bmin.x && pmin.x < bmax.x &&
			pmax.y > bmin.y && pmin.y < bmax.y &&
			pmax.z > bmin.z && pmin.z < bmax.z {
			return true
		}
	}
	return false
}

update :: proc(world: ^ecs.World) {
	players := ecs.slice(world, Player)
	p_entities := ecs.slice_entity(world, Player)
	if len(players) == 0 { return }

	p := &players[0]
	pe := p_entities[0]
	transform := ecs.get_component(world, pe, ecs.Transform3D)
	cam := ecs.get_component(world, pe, ecs.Camera3D)

	dt := rl.GetFrameTime()

	delta := ecs.mouse_delta()
	p.yaw -= delta.x * p.sensitivity
	p.pitch -= delta.y * p.sensitivity
	if p.pitch > 1.4 { p.pitch = 1.4 }
	if p.pitch < -1.4 { p.pitch = -1.4 }

	forward := rl.Vector3{math.sin(p.yaw), 0, math.cos(p.yaw)}
	right := rl.Vector3{-math.cos(p.yaw), 0, math.sin(p.yaw)}
	vel := rl.Vector3{}
	if ecs.is_down(rl.KeyboardKey.W) { vel = vel + forward }
	if ecs.is_down(rl.KeyboardKey.S) { vel = vel - forward }
	if ecs.is_down(rl.KeyboardKey.A) { vel = vel - right }
	if ecs.is_down(rl.KeyboardKey.D) { vel = vel + right }
	if rl.Vector3Length(vel) > 0 {
		vel = rl.Vector3Normalize(vel)
	}
	vel = vel * p.speed
	p.vel.x = vel.x
	p.vel.z = vel.z

	p.vel.y -= 9.8 * dt
	if p.grounded && ecs.is_pressed(rl.KeyboardKey.SPACE) {
		p.vel.y = 5
		p.grounded = false
	}
	if ecs.is_pressed(rl.KeyboardKey.ESCAPE) {
		rl.EnableCursor()
		ecs.exit()
	}

	new_pos := transform.translation

	cand := new_pos
	cand.x += p.vel.x * dt
	if !collides(world, cand, p.eye_height) {
		new_pos.x = cand.x
	} else {
		p.vel.x = 0
	}

	cand = new_pos
	cand.z += p.vel.z * dt
	if !collides(world, cand, p.eye_height) {
		new_pos.z = cand.z
	} else {
		p.vel.z = 0
	}

	cand = new_pos
	cand.y += p.vel.y * dt
	if !collides(world, cand, p.eye_height) {
		new_pos.y = cand.y
		p.grounded = false
	} else {
		if p.vel.y < 0 { p.grounded = true }
		p.vel.y = 0
	}

	transform.translation = new_pos

	cp := math.cos(p.pitch)
	sp := math.sin(p.pitch)
	fwd := rl.Vector3{math.sin(p.yaw) * cp, sp, math.cos(p.yaw) * cp}
	cam.target = transform.translation + fwd
}
