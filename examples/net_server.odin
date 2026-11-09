package main

import "core:fmt"
import "core:os"
import ecs "../src"
import net "../plugins/net"

// example custom replicated component
// @replicated
Health :: struct {
	value: i32,
}

main :: proc() {
	port := 7777
	for a in os.args {
		if len(a) > 7 && a[:7] == "--port=" {
			p := 0
			for c in a[7:] { p = p*10 + int(c - '0') }
			port = p
		}
	}

	net.configure(net.Config{role = .Server, port = port})
	net.replicate(Health)
	net.register_signal(ScoreChanged)

	app: ecs.App
	ecs.add_plugin(&app, net.NetPlugin)
	ecs.add_system(&app, "startup", spawn_world)
	ecs.add_system(&app, "update", server_sim)

	fmt.println("running headless server on port", port)
	ecs.run_headless(&app)
}

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
	// periodically broadcast a game signal
	@(static) counter: int
	counter += 1
	if counter % 120 == 0 {
		net.write_signal(ScoreChanged{player = 1, score = i32(counter)})
	}
}

// example custom networked signal
ScoreChanged :: struct { player: u32, score: i32 }