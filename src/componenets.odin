package shoal

import rl "vendor:raylib"

WindowComponent :: struct {
	width:      i32,
	height:     i32,
	title:      string,
	background: rl.Color,
}
Window: Storage(WindowComponent)

CursorComponent :: struct {
	position: rl.Vector2,
}
Cursor: Storage(CursorComponent)

SpriteComponent :: struct {
	texture: rl.Texture2D,
}
Sprite: Storage(SpriteComponent)

TransformComponent :: struct {
	translation: rl.Vector2,
	rotation:    f32,
}
Transform: Storage(TransformComponent)
