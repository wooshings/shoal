package shoal

import "core:strings"
import rl "vendor:raylib"

// shoal's out-of-the-box behavior. registers, in frame order:
//
//	STARTUP     startup_window (InitWindow from the WindowComponent, 60 fps cap)
//	UPDATE      run_timers, update_cursor_position
//	POST_UPDATE signal_system (clears every signal bus)
//	PRE_DRAW    BeginDrawing + ClearBackground(window.background)
//	DRAW        draw_sprite (each SpriteComponent drawn at its TransformComponent)
//	POST_DRAW   EndDrawing
//	DESTROY     CloseWindow
//
// and spawns two entities: a display holding the default WindowComponent
// (800x600, "shoal window", black background) and a cursor holding a
// CursorComponent. add it before your own systems if you want theirs to run
// first; order within a schedule is registration order
DefaultPlugin :: proc(app: ^App) {
	add_system(app, STARTUP, startup_window)
	add_system(app, DRAW, draw_sprite)
	add_system(app, POST_UPDATE, signal_system)
	add_system(app, UPDATE, run_timers)
	add_system(app, UPDATE, update_cursor_position)
	add_system(app, PRE_DRAW, proc(world: ^World) {rl.BeginDrawing()
		window, _ := single(world, WindowComponent)
		rl.ClearBackground(window.background)})
	add_system(app, POST_DRAW, proc() {rl.EndDrawing()})
	add_system(app, DESTROY, proc() {rl.CloseWindow()})

	// a plugin is one of the few callers that holds an ^App, so it can reach
	// the world through it and set up entities before the frame loop starts
	world := get_world(app)
	display := spawn_entity(world)
	add_component(
		world,
		display,
		WindowComponent{width = 800, height = 600, title = "shoal window", background = rl.BLACK},
	)

	cursor := spawn_entity(world)
	add_component(world, cursor, CursorComponent)
}

@(private)
update_cursor_position :: proc(world: ^World) {
	cursor, _ := single(world, CursorComponent)
	cursor.position = rl.GetMousePosition()
}

@(private)
draw_sprite :: proc(world: ^World) {
	components := slice(world, SpriteComponent)
	entities := slice_entity(world, SpriteComponent)
	for &v, i in components {
		sprite_transform := get_component(world, entities[i], TransformComponent)
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
	window, _ := single(world, WindowComponent)
	rl.InitWindow(window.width, window.height, strings.clone_to_cstring(window.title))
	rl.SetTargetFPS(60)
}
