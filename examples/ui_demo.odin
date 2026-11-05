package main

import ecs "../src"
import ui "../plugins/ui"
import mu "vendor:microui"

main :: proc() {
	app: ecs.App
	ecs.add_plugin(&app, ecs.DefaultPlugin)
	ecs.add_plugin(&app, ui.UIPlugin)
	ecs.add_system(&app, "draw", hello_world)
	ecs.run(&app)

}

hello_world :: proc() {
	if mu.begin_window(ui.get_ctx(), "Test Window", {100, 100, 100, 100}) {
		defer mu.end_window(ui.get_ctx())

		mu.label(ui.get_ctx(), "Hello, world")
	}
}
