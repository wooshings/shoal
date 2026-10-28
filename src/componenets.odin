package shoal

import rl "vendor:raylib"

// what the app's window opens with: size, title, and the clear color
// DefaultPlugin paints at PRE_DRAW
WindowComponent :: struct {
	width:      i32,
	height:     i32,
	title:      string,
	background: rl.Color,
}
// pre-created global storage — just pass &Window, no need to declare it.
// the same goes for every storage in this file
Window: Storage(WindowComponent)

// the mouse position, refreshed every UPDATE by DefaultPlugin
CursorComponent :: struct {
	position: rl.Vector2,
}
Cursor: Storage(CursorComponent)

// a texture DefaultPlugin draws at DRAW, placed by the same entity's
// Transform (so every sprite entity needs a Transform component too)
SpriteComponent :: struct {
	texture: rl.Texture2D,
}
Sprite: Storage(SpriteComponent)

// 2D translation + rotation, read back by draw_sprite when it places the
// entity's Sprite
TransformComponent :: struct {
	translation: rl.Vector2,
	rotation:    f32,
}
Transform: Storage(TransformComponent)
