package main

import ui "../plugins/ui"
import ecs "../src"
import mu "vendor:microui"

main :: proc() {
	app: ecs.App
	ecs.add_plugin(&app, ecs.DefaultPlugin)
	ecs.add_plugin(&app, ui.UIPlugin)
	ecs.add_system(&app, "draw", hello_world)
	ecs.run(&app)

}

hello_world :: proc() {
	if mu.begin_window(ui.get_ctx(), "Test Window", {100, 100, 520, 120}) {
		defer mu.end_window(ui.get_ctx())

		mu.label(ui.get_ctx(), "Hello, world. This is a MicroUI window rendered by raylib.")
	}

	if mu.begin_window(ui.get_ctx(), "Second Test Window", {500, 100, 320, 200}) {
		defer mu.end_window(ui.get_ctx())

		mu.label(ui.get_ctx(), "this is a second test window")
		mu.button(ui.get_ctx(), "button")
	}
}
