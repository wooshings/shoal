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

// audio state: what an entity's Audio component is doing this frame.
AudioState :: enum u8 {
	None,
	Playing,
	Paused,
	Stopped,
}

// an entity-level audio component: add this to any entity that should
// play sounds or music. the AudioSystem processes it every UPDATE.
// one-shot sounds go in `sound`, background music in `music`.
// both can coexist on the same entity (e.g. a radio playing ambient
// music with click sounds).
Audio :: struct {
	sound:   rl.Sound,   // one-shot effect (frameCount == 0 means none)
	music:   rl.Music,   // background music (ctxType == 0 means none)
	state:   AudioState, // what the system should do this frame
	volume:  f32,        // 0.0 .. 1.0 (default 1.0)
	pitch:   f32,        // > 1.0 = higher, < 1.0 = lower (default 1.0)
	pan:     f32,        // -1.0 = left, 0.0 = center, 1.0 = right (default 0.0)
	looping: bool,       // loop music when it reaches the end
}

// components are plain struct declarations. the world holds every storage
// internally, keyed by the component's typeid and created on first add (see
// get_storage in entities.odin), so there's nothing to declare next to a
// component
