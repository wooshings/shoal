package main

import "core:fmt"
import ecs "../src"
import term "../plugins/terminal"

main :: proc() {
	app: ecs.App
	ecs.add_plugin(&app, ecs.HeadlessDefaultPlugin)
	ecs.add_plugin(&app, term.TerminalPlugin)

	ecs.add_system(&app, "startup", proc(world: ^ecs.World) {
		e := ecs.spawn_entity(world)
		ecs.add_component(world, e, ecs.Character{glyph = '@', x = 5, y = 5, fg = .BrightGreen, bold = true})
		for i in 0 ..< 10 {
			e2 := ecs.spawn_entity(world)
			ecs.add_component(world, e2, ecs.Character{glyph = '.', x = i, y = 10, fg = .White})
		}
	})

	fmt.println("terminal demo")
	ecs.run_headless(&app)
}
