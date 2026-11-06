package ui

import ecs "../../src"
import ml "vendor:microui"

// the microui context UIPlugin refreshes every frame, nil until the first
// PRE_DRAW. use get_ctx() instead of touching it directly
ui_ctx: ^ml.Context

// wires the ui package into the app, in frame order:
UIPlugin :: proc(app: ^ecs.App) {
	ecs.init_system_set(app, "draw", "pre_draw", ecs.before("default"))
	ecs.init_system_set(app, "draw", "post_draw", ecs.after("draw"))
	ecs.init_system_set(app, "draw", "late_draw", ecs.before("post_draw"))

	ecs.add_system(app, "startup", proc() {init()})
	ecs.add_system(app, "post_draw", proc() {free_all(context.temp_allocator)})
	ecs.add_system(app, "pre_draw", proc() {ui_ctx = begin()})
	ecs.add_system(app, "late_draw", proc() {end()})
	// the atlas unload lives in its own "atlas" set anchored ahead of
	// "default": DefaultPlugin registers CloseWindow in the destroy default
	// set, and plugin registration (here) lands after it, so an unload
	// appended to default would run with the GL context already gone
	ecs.init_system_set(app, "destroy", "atlas", ecs.before("default"))
	ecs.add_system(app, "atlas", proc() {destroy()})
}

// the microui context for this frame. pass it to every microui call. valid
// from PRE_DRAW onwards (nil before the first frame)
get_ctx :: proc() -> ^ml.Context {
	return ui_ctx
}
