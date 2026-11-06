package main

import ecs "../src"
import defaults "../plugins/defaults"
import rl "vendor:raylib"

main :: proc() {
	app: ecs.App
	ecs.add_plugin(&app, defaults.Batteries)
	ecs.run(&app)
	_ = rl.WHITE
}
