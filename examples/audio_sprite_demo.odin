package main

import "core:fmt"
import "core:strings"
import ecs "../src"
import rl "vendor:raylib"

// demo for the audio and sprite systems. arrow keys cycle sprite properties
// (tint, scale, flip), w/a/s/d cycle sprite sheet cells, j/k/l/i trigger
// audio actions. the sprite rendering draws procedurally (colored
// rectangles), so it runs without any asset files. audio and texture
// loading require actual files on disk — placeholder comments show the
// real API usage.

app: ecs.App

// sprite demo state
ball_color   : rl.Color = rl.BLUE
ball_scale   : rl.Vector2 = {1.0, 1.0}
ball_flip_h  : bool = false
ball_flip_v  : bool = false

// sprite sheet: 4x3 grid, track which cell is selected
sheet_selection: int = 0

// audio demo state
show_audio: bool = true

// main: add DefaultPlugin (window, sprite drawing, cursor, lifecycle),
// add AudioPlugin (audio device init, sound/music processing, cleanup),
// register demo systems, then run. see ecs.DefaultPlugin and AudioPlugin
// in shoal/src for what they do.
main :: proc() {
	ecs.add_plugin(&app, ecs.DefaultPlugin)
	ecs.add_plugin(&app, ecs.AudioPlugin)  // enables audio
	ecs.add_system(&app, ecs.STARTUP, startup_demo)
	ecs.add_system(&app, ecs.UPDATE, update_demo)
	ecs.add_system(&app, ecs.DRAW, draw_demo)
	ecs.run(&app)
}

// startup: placeholder comments showing the real API usage for loading
// sprites, sprite sheets, and audio. see load_sprite, load_sprite_sheet,
// unload_sprite, unload_sprites in systems.odin, and play_sound,
// play_music, stop_sound, stop_music, and the Audio component in
// audio.odin.
startup_demo :: proc(world: ^ecs.World) {
	// load a sprite from file: returns a Sprite with defaults
	// (source = full texture, scale = 1.0, tint = white).
	// in a real game:
	//   sprite := ecs.load_sprite("images/player.png")
	//   ecs.add_component(world, player, sprite)
	//   ecs.add_component(world, player, ecs.Transform{
	//       translation = {400, 300},
	//       rotation    = 0,
	//   })

	// load a sprite sheet: splits a texture into a grid, returns
	// [dynamic]Sprite — each cell shares the same underlying texture
	// but has its own source rect. in a real game:
	//   sprites := ecs.load_sprite_sheet("images/tiles.png", 4, 3)
	//   // sprites[0]  = row 0, col 0 (top-left)
	//   // sprites[5]  = row 1, col 1 (center)
	//   // sprites[11] = row 2, col 3 (bottom-right)
	//   ecs.add_component(world, tile, sprites[5])
	// free all at once:
	//   ecs.unload_sprites(sprites)

	// global audio API:
	// one-shot sounds (cached by path):
	//   h := ecs.play_sound("sounds/explosion.wav")
	//   ecs.set_sound_volume(h, 0.5)
	//   ecs.stop_sound(h)
	//   ecs.is_sound_playing(h)        // → bool
	// background music (streaming):
	//   h := ecs.play_music("sounds/theme.ogg")
	//   ecs.set_music_volume(h, 0.7)
	//   ecs.seek_music(h, 30.0)
	//   ecs.get_music_time_played(h)   // → f32
	//   ecs.get_music_time_length(h)   // → f32
	//   ecs.pause_music(h)
	//   ecs.resume_music(h)
	// master volume (affects all audio):
	//   ecs.set_master_volume(0.8)

	// entity-owned audio (Audio component):
	// add an Audio component to any entity:
	//   ecs.add_component(world, entity, ecs.Audio{
	//       sound   = rl.LoadSoundFromWave(rl.LoadWave("sound.wav")),
	//       state   = ecs.AudioState.Playing,
	//       volume  = 0.8,
	//       pitch   = 1.0,
	//       pan     = 0.0,  // center
	//   })
	// or with music:
	//   ecs.add_component(world, entity, ecs.Audio{
	//       music   = rl.LoadMusicStream("music.ogg"),
	//       state   = ecs.AudioState.Playing,
	//       volume  = 0.5,
	//       looping = true,
	//   })
}

// handle input: arrow keys cycle sprite properties, w/a/s/d cycle sprite
// sheet cells, j/k/l/i trigger audio actions (via GetCharPressed). see
// the Sprite component in componenets.odin and the global API in
// audio.odin.
update_demo :: proc(world: ^ecs.World) {
	// arrow keys: cycle sprite properties

	if rl.IsKeyPressed(rl.KeyboardKey.UP) {
		// cycle tint color (demonstrates the `tint` field)
		switch ball_color {
		case rl.BLUE:
			ball_color = rl.RED
		case rl.RED:
			ball_color = rl.GREEN
		case rl.GREEN:
			ball_color = rl.YELLOW
		case rl.YELLOW:
			ball_color = rl.PURPLE
		default:
			{ ball_color = rl.BLUE }
		}
		fmt.println("Sprite tint → ", color_name(ball_color))
	}

	if rl.IsKeyPressed(rl.KeyboardKey.DOWN) {
		// cycle scale (demonstrates the `scale` field)
		if ball_scale.x == 1.0 {
			ball_scale = {2.0, 2.0}
		} else if ball_scale.x == 2.0 {
			ball_scale = {0.5, 0.5}
		} else {
			ball_scale = {1.0, 1.0}
		}
		fmt.println("Sprite scale → ",
			fmt.tprintf("(%.1f, %.1f)", ball_scale.x, ball_scale.y))
	}

	if rl.IsKeyPressed(rl.KeyboardKey.LEFT) {
		// toggle horizontal flip (demonstrates `flip_h`)
		ball_flip_h = !ball_flip_h
		fmt.println("Sprite flip_h → ", ball_flip_h)
	}

	if rl.IsKeyPressed(rl.KeyboardKey.RIGHT) {
		// toggle vertical flip (demonstrates `flip_v`)
		ball_flip_v = !ball_flip_v
		fmt.println("Sprite flip_v → ", ball_flip_v)
	}

	// w/a/s/d: cycle sprite sheet cells

	// w = next cell, s = previous cell
	if rl.IsKeyPressed(rl.KeyboardKey.W) {
		sheet_selection = (sheet_selection + 1) % 12
	}
	if rl.IsKeyPressed(rl.KeyboardKey.S) {
		if sheet_selection == 0 {
			sheet_selection = 11
		} else {
			sheet_selection -= 1
		}
	}
	// a = previous column (wrap from col 0 → col 3 of previous row)
	if rl.IsKeyPressed(rl.KeyboardKey.A) {
		if sheet_selection % 4 == 0 {
			// at column 0: wrap to column 3 of previous row
			if sheet_selection >= 4 {
				sheet_selection -= 1  // e.g., 4→3, 8→7
			}
			// sheet_selection == 0 stays at 0 (no row above to wrap to)
		} else {
			sheet_selection -= 1
		}
	}
	// d = next column (wrap from col 3 → col 0 of next row)
	if rl.IsKeyPressed(rl.KeyboardKey.D) {
		if sheet_selection % 4 == 3 {
			// at column 3: wrap to column 0 of next row
			if sheet_selection < 8 {
				sheet_selection += 1  // e.g., 3→4, 7→8
			}
			// sheet_selection == 11 stays at 11 (no row below to wrap to)
		} else {
			sheet_selection += 1
		}
	}

	// j/k/l/i: audio actions (via GetCharPressed)
	char := rl.GetCharPressed()
	if char != 0 {
		rune := char
		if rune == 'j' || rune == 'J' {
			// toggle audio info overlay
			show_audio = !show_audio
			fmt.println("Audio overlay → ", show_audio ? "ON" : "OFF")
		}
		if rune == 'k' || rune == 'K' {
			// fire one-shot sound (global API)
			// real usage:
			//   h := ecs.play_sound("sounds/ping.wav")
			//   ecs.set_sound_volume(h, 0.8)
			fmt.println("Sound fired (placeholder — needs actual file)")
		}
		if rune == 'l' || rune == 'L' {
			// entity-owned audio: add an Audio component
			// real usage:
			//   ecs.add_component(world, entity, ecs.Audio{
			//       sound = rl.LoadSoundFromWave(rl.LoadWave("sound.wav")),
			//       state = ecs.AudioState.Playing,
			//       volume = 0.5,
			//   })
			fmt.println("Entity audio added (placeholder — needs actual file)")
		}
		if rune == 'i' || rune == 'I' {
			// unload a sprite (free GPU memory)
			// real usage:
			//   ecs.unload_sprite(sprite)
			fmt.println("Sprite unloaded (placeholder — needs actual texture)")
		}
	}
}

// draw: renders the sprite demo (procedural rectangle), sprite sheet grid,
// and audio info overlay. see draw_sprite in systems.odin, load_sprite
// and load_sprite_sheet in systems.odin, and the global API in audio.odin.
draw_demo :: proc(world: ^ecs.World) {
	// procedural "sprite" — rectangle at center, demonstrating the extended
	// Sprite component fields. in a real game you'd use actual textures:
	//
	//   ecs.add_component(world, player, ecs.Sprite{
	//       texture  = rl.LoadTexture("images/player.png"),
	//       source   = rl.Rectangle{0, 0, 32, 32},  // crop to 32x32
	//       scale    = rl.Vector2{2.0, 2.0},        // 2x scale
	//       tint     = rl.RED,                      // red tint
	//       flip_h   = true,                        // face left
	//   })
	//   ecs.add_component(world, player, ecs.Transform{
	//       translation = {400, 300},
	//       rotation    = 45,                       // 45° rotation
	//   })

	// procedural "sprite" — rectangle at center
	w := f32(64) * ball_scale.x
	h := f32(64) * ball_scale.y

	// handle flip by adjusting position (DrawTexturePro negates dest size)
	draw_x := f32(400)
	draw_y := f32(300)

	if ball_flip_h {
		draw_x = draw_x - w
	}
	if ball_flip_v {
		draw_y = draw_y - h
	}

	rl.DrawRectangle(i32(draw_x), i32(draw_y), i32(w), i32(h), ball_color)
	rl.DrawRectangleLines(
		i32(draw_x), i32(draw_y), i32(w), i32(h), rl.WHITE,
	)

	// sprite sheet demo: draws a 4x3 grid of cells, highlights the selected
	// one. see load_sprite_sheet in systems.odin for the real API.
	sheet_x := f32(600)
	sheet_y := f32(100)
	cell_w  := f32(48)
	cell_h  := f32(48)

	for row := 0; row < 3; row += 1 {
		for col := 0; col < 4; col += 1 {
			idx := row * 4 + col
			cx := sheet_x + f32(col) * (cell_w + f32(4))
			cy := sheet_y + f32(row) * (cell_h + f32(4))

			if idx == sheet_selection {
				rl.DrawRectangle(
					i32(cx), i32(cy), i32(cell_w), i32(cell_h), rl.YELLOW,
				)
				rl.DrawRectangleLines(
					i32(cx), i32(cy), i32(cell_w), i32(cell_h), rl.ORANGE,
				)
			} else {
				rl.DrawRectangle(
					i32(cx), i32(cy), i32(cell_w), i32(cell_h), rl.DARKGRAY,
				)
				rl.DrawRectangleLines(
					i32(cx), i32(cy), i32(cell_w), i32(cell_h), rl.GRAY,
				)
			}

			label := fmt.tprintf("%d", idx)
			rl.DrawText(
				strings.clone_to_cstring(label), i32(cx+16), i32(cy+16),
				16, rl.WHITE,
			)
		}
	}

	// audio info overlay: shows the global API reference. see audio.odin
	// for the full API: play_sound, play_music, stop_sound, stop_music,
	// set_sound_volume, set_music_volume, seek_music,
	// get_music_time_played, get_music_time_length, pause_music,
	// resume_music, set_master_volume, and the Audio component.
	if show_audio {
		rl.DrawText("audio api", 16, 560, 20, rl.LIME)
		rl.DrawText("j — toggle overlay (this text)", 16, 585, 14, rl.GRAY)
		rl.DrawText("k — fire sound (placeholder)", 16, 600, 14, rl.GRAY)
		rl.DrawText("l — entity audio (placeholder)", 16, 615, 14, rl.GRAY)
		rl.DrawText("i — unload sprite (placeholder)", 16, 630, 14, rl.GRAY)
	}

	// sprite info: shows the current sprite state and key bindings
	rl.DrawText("sprite api", 16, 85, 20, rl.LIME)
	rl.DrawText("up — tint (cycle color)", 16, 110, 14, rl.GRAY)
	rl.DrawText("down — scale (cycle size)", 16, 125, 14, rl.GRAY)
	rl.DrawText("left — flip_h (toggle)", 16, 140, 14, rl.GRAY)
	rl.DrawText("right — flip_v (toggle)", 16, 155, 14, rl.GRAY)
	rl.DrawText("w/s/a/d — sheet cell (cycle 0..11)", 16, 170, 14, rl.GRAY)

	// sprite state label
	state := fmt.tprintf(
		"tint=%s scale=(%.1f,%.1f) flip=(%s,%s)",
		color_name(ball_color),
		ball_scale.x, ball_scale.y,
		ball_flip_h ? "H" : "—",
		ball_flip_v ? "V" : "—",
	)
	rl.DrawText(strings.clone_to_cstring(state), 16, 195, 14, rl.WHITE)
}

// helper: returns a string name for a color, used in the state label.
color_name :: proc(c: rl.Color) -> string {
	switch c {
	case rl.BLUE:
		return "blue"
	case rl.RED:
		return "red"
	case rl.GREEN:
		return "green"
	case rl.YELLOW:
		return "yellow"
	case rl.PURPLE:
		return "purple"
	}
	return "custom"
}
