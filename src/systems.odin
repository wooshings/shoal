package shoal

import rl "vendor:raylib"

DefaultPlugin :: proc(app: ^App) {
	add_system(app, DRAW, draw_sprite)

	display := spawn_entity(app)
	add_component(
		display,
		&Window,
		WindowComponent{width = 800, height = 600, title = "shoal window"},
	)
}


draw_sprite :: proc() {
	for i, &v in slice(&Sprite) {
		sprite_transform := get_component(i, &Transform)
		rl.DrawTexture(
			v.texture,
			i32(sprite_transform.translation.x),
			i32(sprite_transform.translation.y),
			rl.WHITE,
		)
	}
}
