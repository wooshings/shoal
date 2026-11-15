package ui

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"
import mu "vendor:microui"
import rl "vendor:raylib"

@(private)
Color32 :: [4]u8

RLMU_State :: struct {
	atlas: rl.Texture2D,
	ctx:   mu.Context,
}

global_state: ^RLMU_State
@(init)
rlmu_init :: proc "contextless" () {
	context = runtime.default_context()
	global_state = new(RLMU_State)
}

init :: proc(state := global_state) {

	pixels := make([]Color32, mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT)

	for alpha, i in mu.default_atlas_alpha do pixels[i] = {255, 255, 255, alpha}

	image := rl.Image {
		data    = raw_data(pixels),
		width   = mu.DEFAULT_ATLAS_WIDTH,
		height  = mu.DEFAULT_ATLAS_HEIGHT,
		format  = .UNCOMPRESSED_R8G8B8A8,
		mipmaps = 1,
	}

	state.atlas = rl.LoadTextureFromImage(image)

	delete(pixels)
	image = {}

	mu.init(ctx = &state.ctx)

	state.ctx.text_width = mu.default_atlas_text_width
	state.ctx.text_height = mu.default_atlas_text_height

	state.ctx.textbox_state.set_clipboard = set_clipboard
	state.ctx.textbox_state.get_clipboard = get_clipboard
}

destroy :: proc(state := global_state) {

	rl.UnloadTexture(state.atlas)
}

begin :: proc(state: ^RLMU_State = global_state) -> ^mu.Context {

	forward_text_input(state)
	forward_mouse_input(state)
	forward_keyboard_input(state)

	mu.begin(&state.ctx)

	return &state.ctx
}

end :: proc(state := global_state) {

	mu.end(&state.ctx)

	current_command: ^mu.Command
	for cmd_variant in mu.next_command_iterator(&state.ctx, &current_command) {
		#partial switch cmd in cmd_variant {

		case ^mu.Command_Text:

			draw_position := [2]i32{cmd.pos.x, cmd.pos.y}
			vla_len := int(cmd.size) - size_of(mu.Command_Text)
			vla_data := ([^]byte)(cmd)[size_of(mu.Command_Text):]
			for i := 0; i < vla_len; i += 1 {
				char := vla_data[i]
				if char & 0xc0 != 0x80 {
					ascii := min(int(char), 127)
					rect := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + ascii]
					draw_mu_atlas_texture(state.atlas, rect, draw_position, cmd.color)
					draw_position.x += rect.w
				}
			}

		case ^mu.Command_Rect:
			rl.DrawRectangle(
				cmd.rect.x,
				cmd.rect.y,
				cmd.rect.w,
				cmd.rect.h,
				transmute(rl.Color)cmd.color,
			)

		case ^mu.Command_Icon:

			rect := mu.default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w - rect.w) / 2
			y := cmd.rect.y + (cmd.rect.h - rect.h) / 2
			draw_mu_atlas_texture(state.atlas, rect, {x, y}, cmd.color)

		case ^mu.Command_Clip:

			rl.EndScissorMode()

			rl.BeginScissorMode(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h)
		}
	}

	rl.EndScissorMode()
}

@(deferred_in = destroy)
init_scope :: proc(state := global_state) -> ^mu.Context {init(state); return &state.ctx}

@(deferred_in = end)
begin_scope :: proc(state := global_state) -> ^mu.Context {begin(state); return &state.ctx}

@(private)
forward_text_input :: proc(state: ^RLMU_State) {

	text_input: [512]byte = ---

	text_input_offset := 0

	for text_input_offset < len(text_input) {

		pressed_rune := rl.GetCharPressed()

		if pressed_rune == 0 do break

		bytes, count := utf8.encode_rune(pressed_rune)

		copy(text_input[text_input_offset:], bytes[:count])

		text_input_offset += count
	}

	mu.input_text(&state.ctx, string(text_input[:text_input_offset]))
}

@(private)
forward_mouse_input :: proc(state: ^RLMU_State) {

	mouse_position := [2]i32{rl.GetMouseX(), rl.GetMouseY()}
	mouse_scroll := rl.GetMouseWheelMove() * -30

	mu.input_mouse_move(&state.ctx, mouse_position.x, mouse_position.y)
	mu.input_scroll(&state.ctx, 0, i32(mouse_scroll))

	MouseButtonMapping :: struct {
		rl: rl.MouseButton,
		mu: mu.Mouse,
	}

	@(static) MouseButtonMappings := [?]MouseButtonMapping {
		{.LEFT, .LEFT},
		{.RIGHT, .RIGHT},
		{.MIDDLE, .MIDDLE},
	}

	for button in MouseButtonMappings {
		if rl.IsMouseButtonPressed(button.rl) {
			mu.input_mouse_down(&state.ctx, mouse_position.x, mouse_position.y, button.mu)
		} else if rl.IsMouseButtonReleased(button.rl) {
			mu.input_mouse_up(&state.ctx, mouse_position.x, mouse_position.y, button.mu)
		}
	}
}

@(private)
forward_keyboard_input :: proc(state: ^RLMU_State) {

	KeyMapping :: struct {
		rl: rl.KeyboardKey,
		mu: mu.Key,
	}

	@(static) KeyMappings := [?]KeyMapping {
		{.LEFT_SHIFT, .SHIFT},
		{.RIGHT_SHIFT, .SHIFT},
		{.LEFT_CONTROL, .CTRL},
		{.RIGHT_CONTROL, .CTRL},
		{.LEFT_ALT, .ALT},
		{.RIGHT_ALT, .ALT},
		{.ENTER, .RETURN},
		{.KP_ENTER, .RETURN},
		{.BACKSPACE, .BACKSPACE},
		{.DELETE, .DELETE},
		{.END, .END},
		{.HOME, .HOME},
		{.LEFT, .LEFT},
		{.RIGHT, .RIGHT},
		{.A, .A},
		{.C, .C},
		{.V, .V},
		{.X, .X},
	}

	for key in KeyMappings {
		if rl.IsKeyPressed(key.rl) {
			mu.input_key_down(&state.ctx, key.mu)
		} else if rl.IsKeyReleased(key.rl) {
			mu.input_key_up(&state.ctx, key.mu)
		}
	}
}

@(private)
draw_mu_atlas_texture :: proc(
	atlas: rl.Texture2D,
	atlas_source: mu.Rect,
	target_position: [2]i32,
	color: mu.Color,
) {

	rl_target_position := rl.Vector2{f32(target_position.x), f32(target_position.y)}
	rl_atlas_source := rl.Rectangle {
		f32(atlas_source.x),
		f32(atlas_source.y),
		f32(atlas_source.w),
		f32(atlas_source.h),
	}

	rl.DrawTextureRec(atlas, rl_atlas_source, rl_target_position, transmute(rl.Color)color)
}

@(private)
set_clipboard :: proc(user_data: rawptr, text: string) -> (ok: bool) {

	ctext, err := strings.clone_to_cstring(text, context.temp_allocator)
	if err == .None {
		rl.SetClipboardText(ctext)
		return true
	}
	return false
}

@(private)
get_clipboard :: proc(user_data: rawptr) -> (text: string, ok: bool) {

	ctext := rl.GetClipboardText()
	if ctext == nil || len(ctext) == 0 {
		ok = false
		return
	}

	clipboard_text, err := strings.clone_from_cstring(ctext, context.temp_allocator)
	text = clipboard_text
	ok = err == .None
	return
}

@(private)
is_utf8_continuation_byte :: proc(char: rune) -> bool {
	return char & 0xc0 == 0x80
}

@(private)
char_to_ascii :: proc(char: rune) -> int {
	return min(int(char), 127)
}
