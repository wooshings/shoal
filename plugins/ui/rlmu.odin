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

// bake the default microui atlas into a raylib texture and set up the mui
// context (text metrics + clipboard callbacks). UIPlugin runs it at STARTUP
init :: proc(state := global_state) {
	// Allocate an array of 32 bit pixel colors for the atlas used by mui
	// An atlas is a big image packed with multiple smaller images. Like a sprite sheet!
	pixels := make([]Color32, mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT)

	// mui has its default atlas already "baked" into a pixel array like ours
	// However it only stores the alpha of each pixel since there are not colors in the atlas
	// We can just copy the alpha values into the alpha channel of our pixels array, leaving the rgb as white
	for alpha, i in mu.default_atlas_alpha do pixels[i] = {255, 255, 255, alpha}

	// Create a raylib Image whose data is the pixels we just allocated
	image := rl.Image {
		data    = raw_data(pixels),
		width   = mu.DEFAULT_ATLAS_WIDTH,
		height  = mu.DEFAULT_ATLAS_HEIGHT,
		format  = .UNCOMPRESSED_R8G8B8A8,
		mipmaps = 1,
	}

	// The image we just created lives on the CPU side of things
	// If we want to actually draw stuff on the GPU we need to create a *Texture*
	// This will actually send the pixel data to the GPU so it can be rendered
	state.atlas = rl.LoadTextureFromImage(image)

	// Now that the pixel data is stored in video memory, we can delete the pixel array in system memory
	delete(pixels)
	image = {}

	// Initialize mui with our mui context
	mu.init(ctx = &state.ctx)
	// and point the text_width/height callback functions of our context to the default ones since we're using the default atlas
	state.ctx.text_width = mu.default_atlas_text_width
	state.ctx.text_height = mu.default_atlas_text_height
	// These variables are actually pointers to `(font: Font, str: string) -> i32` functions,
	// which mui uses to calculate the pixel width/height of a string when rendered with a certain font
	// Let's also assign the clipboard callbacks for copy/paste support. We have our own functions for handling these events.
	state.ctx.textbox_state.set_clipboard = set_clipboard
	state.ctx.textbox_state.get_clipboard = get_clipboard
}

// unload the atlas texture. UIPlugin runs it at DESTROY
destroy :: proc(state := global_state) {
	// Free atlas texture
	rl.UnloadTexture(state.atlas)
}

// forward this frame's raylib input (text, mouse, keys) to microui and start
// the frame. returns the context to build ui against. UIPlugin runs it at
// PRE_DRAW and hands the result to get_ctx()
begin :: proc(state: ^RLMU_State = global_state) -> ^mu.Context {
	// Forward all input from raylib to mui
	// We need to tell mui what keys are pressed, where the mouse is etc so the ui can react accordingly
	forward_text_input(state)
	forward_mouse_input(state)
	forward_keyboard_input(state)

	// Now we can tell mui that we're ready to tell it what UI we want to draw
	mu.begin(&state.ctx)

	return &state.ctx
}

// tell microui the frame is finished, then replay its command list as raylib
// draw calls (and close any lingering scissor). UIPlugin runs it at LATE_DRAW
end :: proc(state := global_state) {
	// Tell mui that we're done drawing ui
	mu.end(&state.ctx)

	// We've "declared" the ui, but it's just a list of commands
	// Now we need to render the UI
	// mui transforms our high-level UI calls into a list of primitive render commands: text, rectangle, icon, clip (masking)
	current_command: ^mu.Command
	for cmd_variant in mu.next_command_iterator(&state.ctx, &current_command) {
		#partial switch cmd in cmd_variant {
		// Draw a (single-line) string
		case ^mu.Command_Text:
			// microui stores commands in a flat byte buffer. text data is
			// appended right after the Command_Text struct as VLA extra bytes.
			// cmd.str is a string header stored inside the struct; its pointer
			// and length may not be correct when read back from the buffer.
			// We compute the VLA length from cmd.size and read bytes directly.
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
		// Draw a rectangle
		case ^mu.Command_Rect:
			rl.DrawRectangle(
				cmd.rect.x,
				cmd.rect.y,
				cmd.rect.w,
				cmd.rect.h,
				transmute(rl.Color)cmd.color,
			)
		// Draw an icon
		case ^mu.Command_Icon:
			// cmd.id stores the index into the default_atlas array of rects which we can use to get the icons atlas rect
			rect := mu.default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w - rect.w) / 2
			y := cmd.rect.y + (cmd.rect.h - rect.h) / 2
			draw_mu_atlas_texture(state.atlas, rect, {x, y}, cmd.color)
		// Start masking what we draw
		case ^mu.Command_Clip:
			// End any previous masking
			rl.EndScissorMode()
			// Begin a mask using the current commands rect
			rl.BeginScissorMode(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h)
		}
	}

	// Make sure we end any lingering scissor mode.
	// Without this precaution it's possible for clipping to persist into the next frame
	// and obstruct stuff until the next clip command from microui is handled!
	rl.EndScissorMode()
}

// init() with destroy() deferred to scope exit: set the ui up and tear it
// down around a block
@(deferred_in = destroy)
init_scope :: proc(state := global_state) -> ^mu.Context {init(state); return &state.ctx}
// begin() with end() deferred to scope exit: a whole frame of ui in one block
@(deferred_in = end)
begin_scope :: proc(state := global_state) -> ^mu.Context {begin(state); return &state.ctx}

// Sends the current text (typing) input from raylib to mui
@(private)
forward_text_input :: proc(state: ^RLMU_State) {
	// Create a buffer to hold UTF8 text input
	// UTF8 is a "variable width encoding" so some characters may be 1 byte whereas other may be up to 4
	text_input: [512]byte = ---
	// This will track the index into the text_input buffer where characters bytes will be copied to
	text_input_offset := 0

	// This loops reads the characters currently pressed until we've read all the pressed characters or we hit the
	// limit of our text input buffer. We'd only hit the limit if someone was holding a LOT of characters
	for text_input_offset < len(text_input) {
		// Get the pressed UTF8 character rune
		// Called multiple times since multiple keys may be pressed
		pressed_rune := rl.GetCharPressed()

		// If the pressed rune (Unicode character) is 0 there are no more keys pressed
		if pressed_rune == 0 do break

		// UTF8 characters are stored using "variable width encoding"
		// This means a character could be represented by 1-4 bytes
		// Encoding the rune into UTF8 always returns 4 bytes, but the count indicates how many runes the character actually is
		bytes, count := utf8.encode_rune(pressed_rune)

		// We'll copy from the start of the bytes array, up to the number of bytes used to represent the character,
		// into our text input buffer at the current text input offset
		copy(text_input[text_input_offset:], bytes[:count])

		// Finally we can offset the text_input_offset by the number of bytes we copied into the buffer
		text_input_offset += count
	}

	// Now we can send our text_input buffer to mui so it knows the currently pressed characters
	// We'll just send a slice of the full text_input buffer, up to the latest input offset since it probably wasn't filled
	mu.input_text(&state.ctx, string(text_input[:text_input_offset]))
}

// Sends the current mouse input from raylib to mui
@(private)
forward_mouse_input :: proc(state: ^RLMU_State) {
	// Get the current mouse position/scroll from raylib
	mouse_position := [2]i32{rl.GetMouseX(), rl.GetMouseY()}
	mouse_scroll := rl.GetMouseWheelMove() * -30

	// Send the mouse position/scroll to mui
	mu.input_mouse_move(&state.ctx, mouse_position.x, mouse_position.y)
	mu.input_scroll(&state.ctx, 0, i32(mouse_scroll))


	// This struct stores a mapping from a raylib mouse button enum to the equivalent mui enum
	MouseButtonMapping :: struct {
		rl: rl.MouseButton,
		mu: mu.Mouse,
	}

	// We'll create an array of mappings using the struct above
	@(static) MouseButtonMappings := [?]MouseButtonMapping {
		{.LEFT, .LEFT},
		{.RIGHT, .RIGHT},
		{.MIDDLE, .MIDDLE},
	}

	// Check each if each mouse button is down or released with Raylib and forward the event to mui if so
	for button in MouseButtonMappings {
		if rl.IsMouseButtonPressed(button.rl) {
			mu.input_mouse_down(&state.ctx, mouse_position.x, mouse_position.y, button.mu)
		} else if rl.IsMouseButtonReleased(button.rl) {
			mu.input_mouse_up(&state.ctx, mouse_position.x, mouse_position.y, button.mu)
		}
	}
}

// Sends the current keyboard input from raylib to mui
// Not quite the same as forward_text_input_to_mui() which sends any pressed *characters*
// whereas this sends specific "modifier" keys like Shift, Enter and Backspace
@(private)
forward_keyboard_input :: proc(state: ^RLMU_State) {
	// This struct stores a mapping from a raylib key enum to the equivalent mui enum
	KeyMapping :: struct {
		rl: rl.KeyboardKey,
		mu: mu.Key,
	}

	// We'll create an array of mappings using the struct above
	// We don't need to map every raylib key - just the ones mui needs for ui stuff
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

// Draws a section of the mui atlas to the screen with a tint
// The target_position it draws to will be the top left of the drawn texture
@(private)
draw_mu_atlas_texture :: proc(
	atlas: rl.Texture2D,
	atlas_source: mu.Rect,
	target_position: [2]i32,
	color: mu.Color,
) {
	// Create a raylib version of the source rect and target position.
	// We don't have to do this for the color since its memory layout is identical
	rl_target_position := rl.Vector2{f32(target_position.x), f32(target_position.y)}
	rl_atlas_source := rl.Rectangle {
		f32(atlas_source.x),
		f32(atlas_source.y),
		f32(atlas_source.w),
		f32(atlas_source.h),
	}

	// Draw the source rect part of the atlas (sprite) to the screen
	// We can transmute the mu.Color to a rl.Color since the memory layout is the same. This is like casting without type-checking
	rl.DrawTextureRec(atlas, rl_atlas_source, rl_target_position, transmute(rl.Color)color)
}

@(private)
set_clipboard :: proc(user_data: rawptr, text: string) -> (ok: bool) {
	// Try and convert the text string handed to us from mui to a cstring, which raylib expects
	ctext, err := strings.clone_to_cstring(text, context.temp_allocator)
	if err == .None {
		rl.SetClipboardText(ctext)
		return true
	}
	return false
}

@(private)
get_clipboard :: proc(user_data: rawptr) -> (text: string, ok: bool) {
	// Try and convert the cstring handed to us from raylib to a string, which mui expects
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

// Checks if the character is a continuation byte in UTF-8 encoding.
// In UTF-8, any byte where the top two bits are 10 (binary 0x80 in hexadecimal) is a continuation byte.
@(private)
is_utf8_continuation_byte :: proc(char: rune) -> bool {
	return char & 0xc0 == 0x80
}

@(private)
char_to_ascii :: proc(char: rune) -> int {
	return min(int(char), 127)
}
