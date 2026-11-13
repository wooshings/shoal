package main

import "core:fmt"
import ecs "../src"
import "core:os"
import term "../plugins/terminal"

main :: proc() {
	app: ecs.App
	ecs.add_plugin(&app, ecs.HeadlessDefaultPlugin)
	ecs.add_plugin(&app, term.TerminalPlugin)

	ecs.add_system(&app, "startup", proc(world: ^ecs.World) {
		// player
		p := ecs.spawn_entity(world)
		ecs.add_component(world, p, ecs.Character{glyph = '@', x = 10, y = 5, fg = .BrightGreen, bold = true})
		// a few walls
		for i in 0 ..< 20 {
			w := ecs.spawn_entity(world)
			ecs.add_component(world, w, ecs.Character{glyph = '#', x = i, y = 12, fg = .BrightBlack})
		}
		// hint text
		t := ecs.spawn_entity(world)
		ecs.add_component(world, t, ecs.Character{text = "arrows/WASD move, mouse clicks place dots, q quits", x = 1, y = 1, fg = .Cyan})
	})

	// movement + mouse interaction + quit
	ecs.add_system(&app, "update", proc(world: ^ecs.World) {
		ents := ecs.slice_entity(world, ecs.Character)
		comps := ecs.slice(world, ecs.Character)
		// find player (first '@'? just use entity 0)
		if len(ents) == 0 { return }
		// player is first spawned entity; locate by glyph
		player_idx := -1
		for i in 0 ..< len(comps) {
			if comps[i].glyph == '@' {
				player_idx = i
				break
			}
		}
		if player_idx >= 0 {
			dx, dy := 0, 0
			if ecs.is_pressed(ecs.UP) || ecs.is_pressed(ecs.W) { dy = -1 }
			if ecs.is_pressed(ecs.DOWN) || ecs.is_pressed(ecs.S) { dy = 1 }
			if ecs.is_pressed(ecs.LEFT) || ecs.is_pressed(ecs.A) { dx = -1 }
			if ecs.is_pressed(ecs.RIGHT) || ecs.is_pressed(ecs.D) { dx = 1 }
			comps[player_idx].x += dx
			comps[player_idx].y += dy
		}

		// mouse click places a dot
		if ecs.mouse_pressed(ecs.MB_LEFT) {
			mx := int(ecs.mouse_position().x)
			my := int(ecs.mouse_position().y)
			d := ecs.spawn_entity(world)
			ecs.add_component(world, d, ecs.Character{glyph = '*', x = mx, y = my, fg = .Yellow})
		}

		// quit on q
		if ecs.is_pressed(ecs.Q) {
			// restore and exit
			fmt.print("\x1b[0m\x1b[?25h\n")
			// force close by setting a flag? run_headless never exits; use os.exit
			os.exit(0)
		}
	})

	fmt.println("terminal demo (q to quit)")
	ecs.run_headless(&app)
}
