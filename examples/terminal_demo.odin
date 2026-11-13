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
		ecs.add_component(world, p, term.Character{glyph = '@', x = 10, y = 5, fg = .BrightGreen, bold = true})
		// a few walls
		for i in 0 ..< 20 {
			w := ecs.spawn_entity(world)
			ecs.add_component(world, w, term.Character{glyph = '#', x = i, y = 12, fg = .BrightBlack})
		}
		// camera (centered, zoom 1)
		cam := ecs.spawn_entity(world)
		ecs.add_component(world, cam, term.TerminalCamera{x = 40, y = 12, zoom = 1})

		// hint text
		t := ecs.spawn_entity(world)
		ecs.add_component(world, t, term.Character{text = "arrows/WASD move, mouse clicks place dots, +/- zoom, q quits", x = 1, y = 1, fg = .Cyan})
	})

	// movement + mouse interaction + quit
	ecs.add_system(&app, "update", proc(world: ^ecs.World) {
		term.ui_begin()
		if term.ui_button("btn1", 2, 2, "Click me", .Black, .Yellow) {
		}
		term.ui_label(2, 4, "Mouse here", .BrightGreen)
		ents := ecs.slice_entity(world, term.Character)
		comps := ecs.slice(world, term.Character)
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
			ecs.add_component(world, d, term.Character{glyph = '*', x = mx, y = my, fg = .Yellow})
		}

		// quit on q
		// zoom controls
		cams := ecs.slice(world, term.TerminalCamera)
		if len(cams) > 0 {
			if ecs.is_pressed(ecs.EQUAL) { cams[0].zoom += 0.25 }
			if ecs.is_pressed(ecs.MINUS) { cams[0].zoom -= 0.25 }
			if cams[0].zoom < 0.25 { cams[0].zoom = 0.25 }
		}

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
