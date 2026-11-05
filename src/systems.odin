package shoal

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// shoal's out-of-the-box behavior. registers, in frame order:
//
//	startup     startup_window (InitWindow from the WindowComponent, 60 fps cap)
//	update      run_timers, update_cursor_position, then the "post_update"
//	            set (signal_system clears every signal bus)
//	draw        pre_draw (BeginDrawing + ClearBackground) -> default
//	            (draw_sprite) -> your declared sets -> post_draw (EndDrawing)
//	destroy     unload_textures (cached sprite textures), CloseWindow, then
//	            the audio plugin's shutdown (unload streams, close device)
//
// and spawns two entities: a display holding the default WindowComponent
// (800x600, "shoal window", black background) and a cursor holding a
// CursorComponent. add it before your own systems if you want theirs to run
// first; order within a schedule is registration order
DefaultPlugin :: proc(app: ^App) {
	// a plugin is one of the few callers that holds an ^App, so it can reach
	// the world through it and set up entities before the frame loop starts
	world := get_world(app)
	display := spawn_entity(world)
	add_component(world, display, Window{800, 600, "shoal window", rl.BLACK})

	cursor := spawn_entity(world)
	add_component(world, cursor, Cursor)

	startup_window(world)

	add_plugin(app, AudioPlugin)
	// add_system(app, "startup", startup_window)

	// a plugin runs when run() starts, i.e. after main() has declared and
	// filled its sets — so the draw pipeline is anchored by name instead of
	// registration order: "pre_draw" is forced to the front (before() with a
	// missing anchor falls back to the front), the engine's own "default"
	// set goes right after it, and "post_draw" is declared last, which
	// appends it after every set main() declared. BeginDrawing always wraps
	// everything, EndDrawing always runs last
	init_system_set(app, "draw", "pre_draw", before("default"))
	init_system_set(app, "draw", "default", after("pre_draw"))
	add_system(app, "pre_draw", proc(world: ^World) {
		window, _ := single(world, Window)
		rl.BeginDrawing()
		rl.ClearBackground(window.background)
	})
	// the root name addresses the engine's own "default" set in "draw"
	add_system(app, "draw", draw_sprite)
	init_system_set(app, "draw", "post_draw")
	add_system(app, "post_draw", proc() {rl.EndDrawing()})

	add_system(app, "update", run_timers)
	add_system(app, "update", update_cursor_position)

	// "post_update" is a child of "update", anchored right after the default
	// set: user logic registered on "update" (and any sets main() declared)
	// runs first, then the signal buses clear, then draw. the run_timers
	// calls above create the default set first, so this anchor resolves
	// instead of falling back to append
	init_system_set(app, "update", "post_update", after("default"))
	add_system(app, "post_update", signal_system)

	// destroy is a real root schedule now (created here), so cleanup runs
	// exactly once, after the frame loop — not every frame under "update".
	// cached textures unload before CloseWindow (registration order within
	// a set), since UnloadTexture needs the GL context alive
	add_system(app, "destroy", unload_textures)
	add_system(app, "destroy", proc() {rl.CloseWindow()})

}

@(private)
update_cursor_position :: proc(world: ^World) {
	cursor, _ := single(world, Cursor)
	cursor.position = rl.GetMousePosition()
}

// draw a sprite using DrawTexturePro, respecting source rect, scale,
// tint, flip, and rotation from TransformComponent. uses zero values
// (empty Rectangle, empty Color) as defaults: empty source means the
// full texture, empty tint means white (no color change). backward
// compatible: a sprite with no extended fields draws exactly as before.
@(private)
draw_sprite :: proc(world: ^World) {
	zero_rect := rl.Rectangle{}
	zero_color := rl.Color{}
	components := slice(world, Sprite)
	entities := slice_entity(world, Sprite)
	for &v, i in components {
		transform := get_component(world, entities[i], Transform)

		// source rect: zero means the whole texture
		source := v.source
		if source == zero_rect {
			source = rl.Rectangle {
				x      = 0,
				y      = 0,
				width  = f32(v.texture.width),
				height = f32(v.texture.height),
			}
		}

		if v.scale.x == 0 {v.scale.x = 1}
		if v.scale.y == 0 {v.scale.y = 1}

		// destination size: source scaled
		dest_w := source.width * v.scale.x
		dest_h := source.height * v.scale.y

		// flip by negating destination size (DrawTexturePro handles this)
		if v.flip_h {
			dest_w = -dest_w
		}
		if v.flip_v {
			dest_h = -dest_h
		}

		// origin at center of source (rotation pivot) — Vector2 is positional
		origin := rl.Vector2{source.width * 0.5 * v.scale.x, source.height * 0.5 * v.scale.y}

		// destination rectangle (top-left from Transform, size from scale+flip)
		dest := rl.Rectangle {
			x      = transform.translation.x,
			y      = transform.translation.y,
			width  = dest_w,
			height = dest_h,
		}

		// tint: default WHITE means no color change
		tint := v.tint
		if tint == zero_color {
			tint = rl.WHITE
		}

		rl.DrawTexturePro(v.texture, source, dest, origin, transform.rotation, tint)
	}
}

// textures are cached by path — the path is the handle, same rule as audio:
// first call loads from disk, every call after returns the same texture. the
// cache owns every texture and frees them all at "destroy"
@(private)
textures: map[string]rl.Texture

// cache lookup or disk load. panics on a path that can't be loaded: raylib
// returns a zeroed texture (id 0) on failure and drawing it renders nothing —
// a typo'd asset path would just show blank forever. same fail-fast rule as
// play_sound and add_system
@(private)
get_texture :: proc(path: string) -> rl.Texture {
	if t, ok := textures[path]; ok {
		return t
	}
	t := rl.LoadTexture(strings.clone_to_cstring(path))
	if t.id == 0 {
		panic(fmt.tprintf("load_sprite: could not load texture %q", path))
	}
	textures[path] = t
	return t
}

// free every cached texture. registered ahead of CloseWindow — UnloadTexture
// needs the GL context alive
@(private)
unload_textures :: proc() {
	for _, t in textures {
		rl.UnloadTexture(t)
	}
	delete(textures)
}

// load a sprite from a file path. returns a Sprite with the loaded texture
// and default extended fields (full source, 1.0 scale, white tint). textures
// are cached by path: repeated calls return the same texture instead of
// reloading, so spawning a hundred entities from one png costs one load.
// the cache owns the textures — there is no per-sprite unload; everything
// is freed at "destroy". a path that can't be loaded panics with the path
//
//     sprite := load_sprite("images/player.png")
//     ecs.add_component(world, entity, sprite)
load_sprite :: proc(path: string) -> Sprite {
	texture := get_texture(path)
	return Sprite {
		texture = texture,
		source = rl.Rectangle{},
		scale = rl.Vector2{1.0, 1.0},
		tint = rl.WHITE,
	}
}

// load a sprite sheet and split it into individual sprites.
// cols and rows define the grid. returns a slice of Sprites, one per cell.
// the sheet's texture is cached by path like load_sprite, and all returned
// sprites share that one cached texture
//
//     sprites := load_sprite_sheet("images/sprites.png", 4, 3)
//     // sprites[0] is top-left, sprites[11] is bottom-right
load_sprite_sheet :: proc(path: string, cols, rows: int) -> [dynamic]Sprite {
	texture := get_texture(path)

	cell_w := f32(texture.width) / f32(cols)
	cell_h := f32(texture.height) / f32(rows)

	sprites := [dynamic]Sprite{}
	for row := 0; row < rows; row += 1 {
		for col := 0; col < cols; col += 1 {
			append(
				&sprites,
				Sprite {
					texture = texture,
					source = rl.Rectangle {
						x = f32(col) * cell_w,
						y = f32(row) * cell_h,
						width = cell_w,
						height = cell_h,
					},
					scale = rl.Vector2{1.0, 1.0},
					tint = rl.WHITE,
				},
			)
		}
	}
	return sprites
}

@(private)
startup_window :: proc(world: ^World) {
	window, _ := single(world, Window)
	rl.InitWindow(window.width, window.height, strings.clone_to_cstring(window.title))
	rl.SetTargetFPS(60)
	fmt.println("Window Initialized")
}
