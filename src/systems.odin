package shoal

import "core:strings"
import rl "vendor:raylib"

// shoal's out-of-the-box behavior. registers, in frame order:
//
//	startup     startup_window (InitWindow from the WindowComponent, 60 fps cap)
//	update      run_timers, update_cursor_position, then the "post_update"
//	            set (signal_system clears every signal bus)
//	draw        pre_draw (BeginDrawing + ClearBackground) -> default
//	            (draw_sprite) -> your declared sets -> post_draw (EndDrawing)
//	destroy     CloseWindow
//
// and spawns two entities: a display holding the default WindowComponent
// (800x600, "shoal window", black background) and a cursor holding a
// CursorComponent. add it before your own systems if you want theirs to run
// first; order within a schedule is registration order
DefaultPlugin :: proc(app: ^App) {
	add_system(app, "startup", startup_window)

	// a plugin runs when run() starts, i.e. after main() has declared and
	// filled its sets — so the draw pipeline is anchored by name instead of
	// registration order: "pre_draw" is forced to the front (before() with a
	// missing anchor falls back to the front), the engine's own "default"
	// set goes right after it, and "post_draw" is declared last, which
	// appends it after every set main() declared. BeginDrawing always wraps
	// everything, EndDrawing always runs last
	init_system_set(app, "draw", "pre_draw", before("default"))
	init_system_set(app, "draw", "default", after("pre_draw"))
	add_system(app, "pre_draw", proc(world: ^World) {
		window, _ := single(world, Window)
		rl.BeginDrawing()
		rl.ClearBackground(window.background)
	})
	// the root name addresses the engine's own "default" set in "draw"
	add_system(app, "draw", draw_sprite)
	init_system_set(app, "draw", "post_draw")
	add_system(app, "post_draw", proc() {rl.EndDrawing()})

	add_system(app, "update", run_timers)
	add_system(app, "update", update_cursor_position)

	// "post_update" is a child of "update", anchored right after the default
	// set: user logic registered on "update" (and any sets main() declared)
	// runs first, then the signal buses clear, then draw. the run_timers
	// calls above create the default set first, so this anchor resolves
	// instead of falling back to append
	init_system_set(app, "update", "post_update", after("default"))
	add_system(app, "post_update", signal_system)

	// destroy is a real root schedule now (created here), so CloseWindow
	// runs exactly once, after the frame loop — not every frame under
	// "update"
	add_system(app, "destroy", proc() {rl.CloseWindow()})

	// a plugin is one of the few callers that holds an ^App, so it can reach
	// the world through it and set up entities before the frame loop starts
	world := get_world(app)
	display := spawn_entity(world)
	add_component(
		world,
		display,
		Window{800, 600, "shoal window", rl.BLACK},
	)

	cursor := spawn_entity(world)
	add_component(world, cursor, Cursor)
}

@(private)
update_cursor_position :: proc(world: ^World) {
	cursor, _ := single(world, Cursor)
	cursor.position = rl.GetMousePosition()
}

@(private)
draw_sprite :: proc(world: ^World) {
	components := slice(world, Sprite)
	entities := slice_entity(world, Sprite)
	for &v, i in components {
		sprite_transform := get_component(world, entities[i], Transform)
		rl.DrawTexture(
			v.texture,
			i32(sprite_transform.translation.x),
			i32(sprite_transform.translation.y),
			rl.WHITE,
		)
	}
}

@(private)
startup_window :: proc(world: ^World) {
	window, _ := single(world, Window)
	rl.InitWindow(window.width, window.height, strings.clone_to_cstring(window.title))
	rl.SetTargetFPS(60)
}
