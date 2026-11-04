package shoal

import rl "vendor:raylib"

// what the app's window opens with: size, title, and the clear color.
// DefaultPlugin opens the window from it at "startup" and paints the clear
// color at "pre_draw" (inline in the "draw" schedule)
Window :: struct {
	width:      i32,
	height:     i32,
	title:      string,
	background: rl.Color,
}

// the mouse position, refreshed every UPDATE by DefaultPlugin
Cursor :: struct {
	position: rl.Vector2,
}

// a texture DefaultPlugin draws at DRAW, placed by the same entity's
// TransformComponent (so every sprite entity needs a Transform component
// too). extended fields:
//   source:   crop to a region of the texture (sprite sheets)
//   scale:    scale the sprite (default 1.0, 1.0)
//   tint:     color tint (default WHITE)
//   flip_h/v: flip the sprite horizontally/vertically
Sprite :: struct {
	texture:  rl.Texture2D,
	source:   rl.Rectangle,  // zero = whole texture
	scale:    rl.Vector2,    // default 1.0, 1.0
	tint:     rl.Color,      // default WHITE
	flip_h:   bool,
	flip_v:   bool,
}

// 2D translation + rotation, read back by draw_sprite when it places the
// entity's SpriteComponent
Transform :: struct {
	translation: rl.Vector2,
	rotation:    f32,
}

// components are plain struct declarations. the world holds every storage
// internally, keyed by the component's typeid and created on first add (see
// get_storage in entities.odin), so there's nothing to declare next to a
// component
