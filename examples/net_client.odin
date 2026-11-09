package main

import "core:fmt"
import "core:os"
import ecs "../src"
import net "../plugins/net"
import rl "vendor:raylib"

// example custom replicated component
// @replicated
Health :: struct {
	value: i32,
}

// example custom networked signal
ScoreChanged :: struct { player: u32, score: i32 }

net_events_plugin :: proc(app: ^ecs.App) {
	ecs.init_system_set(app, "update", "net_events", ecs.before("post_update"))
	ecs.add_system(app, "net_events", on_net_events)
}

main :: proc() {
	port := 7777
	host := "127.0.0.1"
	for a in os.args {
		if len(a) > 7 && a[:7] == "--port=" {
			p := 0
			for c in a[7:] { p = p*10 + int(c - '0') }
			port = p
		} else if len(a) > 7 && a[:7] == "--host=" {
			host = a[7:]
		}
	}

	net.configure(net.Config{role = .Client, host = host, port = port})
	net.replicate(Health)
	net.register_signal(ScoreChanged)

	app: ecs.App
	ecs.add_plugin(&app, ecs.DefaultPlugin)
	ecs.add_plugin(&app, net.NetPlugin)
	ecs.add_plugin(&app, net_events_plugin)
	ecs.add_system(&app, "update", client_input)
	ecs.add_system(&app, "draw", draw_world)
	ecs.run(&app)
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

on_net_events :: proc(world: ^ecs.World) {
	for s in ecs.read(net.ClientConnected) {
		fmt.println("SIGNAL: client connected, id=", s.id)
	}
	for s in ecs.read(net.ClientDisconnected) {
		fmt.println("SIGNAL: client disconnected, id=", s.id)
	}
	for s in ecs.read(ScoreChanged) {
		fmt.println("SIGNAL: score changed, player=", s.player, "score=", s.score)
	}
	_ = world
}