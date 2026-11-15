package ui

import ecs "../../src"
import ml "vendor:microui"

ui_ctx: ^ml.Context

UIPlugin :: proc(app: ^ecs.App) {
	ecs.init_system_set(app, "draw", "pre_draw", ecs.before("default"))
	ecs.init_system_set(app, "draw", "post_draw", ecs.after("draw"))
	ecs.init_system_set(app, "draw", "late_draw", ecs.before("post_draw"))

	ecs.add_system(app, "startup", proc() {init()})
	ecs.add_system(app, "post_draw", proc() {free_all(context.temp_allocator)})
	ecs.add_system(app, "pre_draw", proc() {ui_ctx = begin()})
	ecs.add_system(app, "late_draw", proc() {end()})

	ecs.init_system_set(app, "destroy", "atlas", ecs.before("default"))
	ecs.add_system(app, "atlas", proc() {destroy()})
}

get_ctx :: proc() -> ^ml.Context {
	return ui_ctx
}
