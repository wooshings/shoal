package shoal

import "core:strings"
import rl "vendor:raylib"

DefaultPlugin :: proc(app: ^App) {
	add_system(app, STARTUP, startup_window)
	add_system(app, DRAW, draw_sprite)
	add_system(app, POST_UPDATE, signal_system)
	add_system(app, UPDATE, run_timers)
	add_system(app, UPDATE, update_cursor_position)
	add_system(app, PRE_DRAW, proc() {rl.BeginDrawing()
		window, _ := single(&Window)
		rl.ClearBackground(window.background)})
	add_system(app, POST_DRAW, proc() {rl.EndDrawing()})
	add_system(app, DESTROY, proc() {rl.CloseWindow()})

	display := spawn_entity(app)
	add_component(
		display,
		&Window,
		WindowComponent{width = 800, height = 600, title = "shoal window", background = rl.BLACK},
	)

	cursor := spawn_entity(app)
	add_component(cursor, &Cursor)
}

@(private)
update_cursor_position :: proc() {
	cursor, _ := single(&Cursor)
	cursor.position = rl.GetMousePosition()
}

@(private)
draw_sprite :: proc() {
	components := slice(&Sprite)
	entities := slice_entity(&Sprite)
	for &v, i in components {
		sprite_transform := get_component(entities[i], &Transform)
		rl.DrawTexture(
			v.texture,
			i32(sprite_transform.translation.x),
			i32(sprite_transform.translation.y),
			rl.WHITE,
		)
	}
}

@(private)
startup_window :: proc() {
	window, _ := single(&Window)
	rl.InitWindow(window.width, window.height, strings.clone_to_cstring(window.title))
	rl.SetTargetFPS(60)
}
