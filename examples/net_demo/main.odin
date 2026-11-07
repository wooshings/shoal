package main

import "core:fmt"
import "core:os"
import ecs "../../src"
import net "../../plugins/net"
import rl "vendor:raylib"

// example custom replicated component
// @replicated
Health :: struct {
	value: i32,
}


main :: proc() {
	args := os.args
	server_mode := false
	// allow selecting role via env var (handy for `odin run ...` where
	// CLI flags are consumed by the compiler: SHOAL_SERVER=1 odin run ...)
	if v, ok := os.lookup_env_alloc("SHOAL_SERVER", context.temp_allocator); ok && (v == "1" || v == "true" || v == "yes") {
		server_mode = true
	}
	port := 7777
	host := "127.0.0.1"

	for a in args {
		if a == "--server" {
			server_mode = true
		} else if len(a) > 7 && a[:7] == "--port=" {
			p := 0
			for c in a[7:] { p = p*10 + int(c - '0') }
			port = p
		} else if len(a) > 7 && a[:7] == "--host=" {
			host = a[7:]
		}
	}

	if server_mode {
		net.configure(net.Config{role = .Server, port = port})
		register_replicated_components()
		app: ecs.App
		ecs.add_plugin(&app, net.NetPlugin)
		ecs.add_system(&app, "startup", spawn_world)
		ecs.add_system(&app, "update", server_sim)
		fmt.println("running headless server on port", port)
		ecs.run_headless(&app)
	} else {
		net.configure(net.Config{role = .Client, host = host, port = port})
		register_replicated_components()
		app: ecs.App
		ecs.add_plugin(&app, ecs.DefaultPlugin)
		ecs.add_plugin(&app, net.NetPlugin)
		ecs.add_system(&app, "update", client_input)
		ecs.add_system(&app, "draw", draw_world)
		ecs.run(&app)
	}
}

// shared world setup: server spawns the replicated entities
spawn_world :: proc(world: ^ecs.World) {
	for i in 0 ..< 5 {
		e := ecs.spawn_entity(world)
		ecs.add_component(world, e, net.Networked{id = 0, owner = 0})
		ecs.add_component(world, e, ecs.Transform{translation = {200 + f32(i)*60, 200}, rotation = 0})
		ecs.add_component(world, e, Health{value = 100})
	}
}

server_sim :: proc(world: ^ecs.World) {
	ents := ecs.slice_entity(world, net.Networked)
	for i in 0 ..< len(ents) {
		n := ecs.slice(world, net.Networked)[i]
		if n.owner != 0 { continue } // only move server-owned
		tr, _ := ecs.try_get_component(world, ents[i], ecs.Transform)
		tr.translation.x += 1
		if tr.translation.x > 700 { tr.translation.x = 100 }
	}
}

client_input :: proc(world: ^ecs.World) {
	ents := ecs.slice_entity(world, net.Networked)
	for i in 0 ..< len(ents) {
		n := ecs.slice(world, net.Networked)[i]
		if n.owner != 1 { continue }
		tr, _ := ecs.try_get_component(world, ents[i], ecs.Transform)
		speed: f32 = 3
		if rl.IsKeyDown(rl.KeyboardKey.LEFT)  { tr.translation.x -= speed }
		if rl.IsKeyDown(rl.KeyboardKey.RIGHT) { tr.translation.x += speed }
		if rl.IsKeyDown(rl.KeyboardKey.UP)    { tr.translation.y -= speed }
		if rl.IsKeyDown(rl.KeyboardKey.DOWN)  { tr.translation.y += speed }
	}
}

draw_world :: proc(world: ^ecs.World) {
	ents := ecs.slice_entity(world, net.Networked)
	for i in 0 ..< len(ents) {
		n := ecs.slice(world, net.Networked)[i]
		tr, _ := ecs.try_get_component(world, ents[i], ecs.Transform)
		color := rl.BLUE
		if n.owner == 1 { color = rl.RED }
		rl.DrawCircle(i32(tr.translation.x), i32(tr.translation.y), 10, color)
	}
}