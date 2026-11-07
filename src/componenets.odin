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

// build a sprite with the common defaults already in place — full texture,
// natural size (1.0), white tint — so call sites only pass what they want
// to change. odin only allows default values on procedures (struct fields
// can't declare them), so this is the "defaults included" constructor:
//
//	sprite := ecs.sprite(tex)                       // natural size, untinted
//	sprite := ecs.sprite(tex, scale = {0.2, 0.2})   // shrunk, purple below
sprite :: proc(
	texture: rl.Texture2D,
	scale := rl.Vector2{1, 1},
	tint := rl.WHITE,
	source := rl.Rectangle{},
) -> Sprite {
	return Sprite{texture = texture, scale = scale, tint = tint, source = source}
}

// 2D translation + rotation, read back by draw_sprite when it places the
// entity's SpriteComponent
Transform :: struct {
	translation: rl.Vector2,
	rotation:    f32,
}

// marks its entity as a 2d camera. rendering through the camera is centered
// on the look-at: this entity's own TransformComponent, whose translation is
// the world point that appears at the viewport center and whose rotation is
// the camera roll around that point — move the camera by writing the
// transform, the same way you move any other entity. projection state lives
// here:
//   zoom: world scale (2.0 = everything twice as big), zero = 1.0
// a world with no Camera component renders in plain screen space; with one,
// the first-registered camera acts (see CameraPlugin in camera.odin)
Camera :: struct {
	zoom: f32,
}

// components are plain struct declarations. the world holds every storage
// internally, keyed by the component's typeid and created on first add (see
// get_storage in entities.odin), so there's nothing to declare next to a
// component
