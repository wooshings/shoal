package shoal

import rl "vendor:raylib"

SpriteComponent :: struct {
	texture: rl.Texture2D,
}
Sprite: Storage(SpriteComponent)

TransformComponent :: struct {
	translation: rl.Vector2,
	rotation:    int,
}
Transform: Storage(TransformComponent)
