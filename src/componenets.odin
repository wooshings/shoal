package shoal

import rl "vendor:raylib"

// what the app's window opens with: size, title, and the clear color.
// DefaultPlugin opens the window from it at STARTUP and paints the clear
// color at PRE_DRAW
WindowComponent :: struct {
	width:      i32,
	height:     i32,
	title:      string,
	background: rl.Color,
}

// the mouse position, refreshed every UPDATE by DefaultPlugin
CursorComponent :: struct {
	position: rl.Vector2,
}

// a texture DefaultPlugin draws at DRAW, placed by the same entity's
// TransformComponent (so every sprite entity needs a Transform component
// too)
SpriteComponent :: struct {
	texture: rl.Texture2D,
}

// 2D translation + rotation, read back by draw_sprite when it places the
// entity's SpriteComponent
TransformComponent :: struct {
	translation: rl.Vector2,
	rotation:    f32,
}

// components are plain struct declarations. the world holds every storage
// internally, keyed by the component's typeid and created on first add (see
// get_storage in entities.odin), so there's nothing to declare next to a
// component
