package ui

import ecs "../src"
import ml "vendor:microui"

// the microui context UIPlugin refreshes every frame, nil until the first
// PRE_DRAW. use get_ctx() instead of touching it directly
ui_ctx: ^ml.Context

// wires the ui package into the app, in frame order:
//
//	STARTUP     init() bakes the microui atlas into a texture
//	PRE_DRAW    begin() forwards raylib input, starts the frame, stashes ui_ctx
//	POST_DRAW   the frame's temp arena is freed, then end() renders the ui
//	DESTROY     destroy() unloads the atlas texture
//
// (systems within a schedule run in registration order, so POST_DRAW frees
// the arena first and renders second)
UIPlugin :: proc(app: ^ecs.App) {
	ecs.add_system(app, ecs.STARTUP, proc() {init()})
	ecs.add_system(app, ecs.POST_DRAW, proc() {free_all(context.temp_allocator)})
	ecs.add_system(app, ecs.PRE_DRAW, proc() {ui_ctx = begin()})
	ecs.add_system(app, ecs.POST_DRAW, proc() {end()})
	ecs.add_system(app, ecs.DESTROY, proc() {destroy()})
}

// the microui context for this frame. pass it to every microui call. valid
// from PRE_DRAW onwards (nil before the first frame)
get_ctx :: proc() -> ^ml.Context {
	return ui_ctx
}
