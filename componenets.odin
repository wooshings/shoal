package shoal

import rl "vendor:raylib"

WindowComponent :: struct {
	width:  i32,
	height: i32,
	title:  string,
}
Window: Storage(WindowComponent)

SpriteComponent :: struct {
	texture: rl.Texture2D,
}
Sprite: Storage(SpriteComponent)

TransformComponent :: struct {
	translation: rl.Vector2,
	rotation:    f32,
}
Transform: Storage(TransformComponent)
