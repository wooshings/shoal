package shoal

import rl "vendor:raylib"

Sprite :: struct {
	texture: rl.Texture2D,
}
sprites: Storage(Sprite)

Transform :: struct {
	translation: rl.Vector2,
	rotation:    int,
}
transforms: Storage(Transform)
