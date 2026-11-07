package main

import "core:fmt"
import "core:os"
import "core:time"
import ecs "../src"
import net "../plugins/net"
import rl "vendor:raylib"

server_mode := false

main :: proc() {
	args := os.args
	port: int = 7777
	host := "127.0.0.1"

	for a in args {
		if a == "--server" {
			server_mode = true
		} else if len(a) > 7 && a[:7] == "--port=" {
			p := 0
			for c in a[7:] {
				p = p*10 + int(c - '0')
			}
			port = p
		} else if len(a) > 7 && a[:7] == "--host=" {
			host = a[7:]
		}
	}

	if server_mode {
		net.configure(net.Config{role = .Server, port = port})
		app: ecs.App
		ecs.add_plugin(&app, net.NetPlugin)
		ecs.add_system(&app, "startup", spawn_server_entities)
		ecs.add_system(&app, "update", move_server_entities)
		// run plugins + startup
		for p in app.plugins { p(&app) }
		ecs.run_schedule(&app, "startup")
		fmt.println("running headless server on port", port)
		for {
			ecs.run_schedule(&app, "update")
			time.sleep(16 * time.Millisecond)
		}
	} else {
		net.configure(net.Config{role = .Client, host = host, port = port})
		app: ecs.App
		ecs.add_plugin(&app, ecs.DefaultPlugin)
		ecs.add_plugin(&app, net.NetPlugin)
		ecs.add_system(&app, "draw", draw_entities)
		ecs.run(&app)
	}
}

spawn_server_entities :: proc(world: ^ecs.World) {
	for i in 0 ..< 5 {
		e := ecs.spawn_entity(world)
		ecs.add_component(world, e, net.Networked{id = 0, owner = 0})
		ecs.add_component(world, e, ecs.Transform{translation = {200 + f32(i)*60, 200}, rotation = 0})
	}
}

move_server_entities :: proc(world: ^ecs.World) {
	t := f32(0) // placeholder
	_ = t
	ents := ecs.slice_entity(world, net.Networked)
	for i in 0 ..< len(ents) {
		tr, _ := ecs.try_get_component(world, ents[i], ecs.Transform)
		tr.translation.x += 1
		if tr.translation.x > 700 { tr.translation.x = 100 }
	}
}

draw_entities :: proc(world: ^ecs.World) {
	ents := ecs.slice_entity(world, net.Networked)
	for i in 0 ..< len(ents) {
		tr, _ := ecs.try_get_component(world, ents[i], ecs.Transform)
		rl.DrawCircle(i32(tr.translation.x), i32(tr.translation.y), 10, rl.BLUE)
	}
}
