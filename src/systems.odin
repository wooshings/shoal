package shoal

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

ExitApp :: struct {}

exit :: proc() { write(ExitApp{}) }

DefaultPlugin :: proc(app: ^App) {

	world := get_world(app)

	if len(slice(world, Window)) == 0 {
		display := spawn_entity(world)
		add_component(world, display, Window{800, 600, "shoal window", rl.BLACK})
	}

	cursor := spawn_entity(world)
	add_component(world, cursor, Cursor)

	add_plugin(app, AudioPlugin)
	add_plugin(app, InputPlugin)

	init_system_set(app, "startup", "window", before("default"))
	add_system(app, "window", startup_window)

	init_system_set(app, "draw", "pre_draw", before("default"))
	init_system_set(app, "draw", "default", after("pre_draw"))
	add_system(app, "pre_draw", proc(world: ^World) {
		window, _ := single(world, Window)
		bg := window.background
		if bg == (rl.Color{}) {
			bg = rl.BLACK
		}
		rl.BeginDrawing()
		rl.ClearBackground(bg)
	})

	add_system(app, "draw", draw_sprite)
	init_system_set(app, "draw", "post_draw")
	add_system(app, "post_draw", proc() {rl.EndDrawing()})

	add_system(app, "update", run_timers)
	add_system(app, "update", update_cursor_position)

	init_system_set(app, "update", "post_update", after("default"))
	add_system(app, "post_update", signal_system)

	add_system(app, "destroy", unload_textures)
	add_system(app, "destroy", proc() {rl.CloseWindow()})

}

@(private)
update_cursor_position :: proc(world: ^World) {
	cursor, _ := single(world, Cursor)
	cursor.position = rl.GetMousePosition()
}

@(private)
draw_sprite :: proc(world: ^World) {
	zero_rect := rl.Rectangle{}
	zero_color := rl.Color{}
	components := slice(world, Sprite)
	entities := slice_entity(world, Sprite)
	for &v, i in components {
		transform := get_component(world, entities[i], Transform)

		source := v.source
		if source == zero_rect {
			source = rl.Rectangle {
				x      = 0,
				y      = 0,
				width  = f32(v.texture.width),
				height = f32(v.texture.height),
			}
		}

		scale := v.scale
		if scale.x == 0 {scale.x = 1}
		if scale.y == 0 {scale.y = 1}

		dest_w := source.width * scale.x
		dest_h := source.height * scale.y

		if v.flip_h {
			dest_w = -dest_w
		}
		if v.flip_v {
			dest_h = -dest_h
		}

		origin := rl.Vector2{source.width * 0.5 * scale.x, source.height * 0.5 * scale.y}

		dest := rl.Rectangle {
			x      = transform.translation.x,
			y      = transform.translation.y,
			width  = dest_w,
			height = dest_h,
		}

		tint := v.tint
		if tint == zero_color {
			tint = rl.WHITE
		}

		rl.DrawTexturePro(v.texture, source, dest, origin, transform.rotation, tint)
	}
}

textures: map[string]rl.Texture

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

unload_textures :: proc() {
	for _, t in textures {
		rl.UnloadTexture(t)
	}
	delete(textures)
}

load_sprite :: proc(path: string) -> Sprite {
	texture := get_texture(path)

	return sprite(texture)
}

load_sprite_sheet :: proc(path: string, cols, rows: int) -> [dynamic]Sprite {
	texture := get_texture(path)

	cell_w := f32(texture.width) / f32(cols)
	cell_h := f32(texture.height) / f32(rows)

	sprites := [dynamic]Sprite{}
	for row := 0; row < rows; row += 1 {
		for col := 0; col < cols; col += 1 {
			append(
				&sprites,
				sprite(
					texture,
					source = rl.Rectangle {
						x = f32(col) * cell_w,
						y = f32(row) * cell_h,
						width = cell_w,
						height = cell_h,
					},
				),
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
	rl.SetExitKey(rl.KeyboardKey(0))
}
