package main

import "core:fmt"
import "core:os"
import ecs "../src"
import term "../plugins/terminal"

main :: proc() {
	app: ecs.App
	ecs.add_plugin(&app, ecs.HeadlessDefaultPlugin)
	ecs.add_plugin(&app, term.TerminalPlugin)

	ecs.add_system(&app, "startup", proc(world: ^ecs.World) {
	})

	ecs.add_system(&app, "update", proc(world: ^ecs.World) {
		term.ui_begin()
		term.ui_label(2, 2, "HELLO UI", .BrightMagenta)
		if term.ui_button("b", 2, 4, "BUTTON", .Black, .Green) {
		}
	})

	fmt.println("ui demo (q to quit)")
	ecs.add_system(&app, "update", proc(world: ^ecs.World) {
		if ecs.is_pressed(ecs.Q) { fmt.print("\x1b[0m\x1b[?25h\n"); os.exit(0) }
	})
	ecs.run_headless(&app)
}
