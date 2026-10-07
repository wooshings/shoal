package shoal

import rl "vendor:raylib"

DefaultPlugin :: proc(app: ^App) {
	add_system(app, DRAW, draw_sprite)
}

draw_sprite :: proc() {
	for i, &v in sprites.data {
		sprite_transform := transforms.data[i]
		rl.DrawTexture(
			v.texture,
			i32(sprite_transform.translation.x),
			i32(sprite_transform.translation.y),
			rl.WHITE,
		)
	}
}
