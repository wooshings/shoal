package shoal

import rl "vendor:raylib"

DefaultPlugin :: proc(app: ^App) {
	add_system(app, DRAW, draw_sprite)
	add_system(app, UPDATE, signal_system)
	add_system(app, UPDATE, run_timers)
	add_system(app, UPDATE, update_cursor_position)

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
