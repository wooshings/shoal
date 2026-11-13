package shoal

import "core:fmt"
import rl "vendor:raylib"

// the raylib-backed input snapshot. polled once per frame by the plugin's
// "input" set, which is anchored ahead of "default" in the "update" walk,
// so every user update system reads a fresh, complete frame of state — same
// anchoring trick audio_init uses in "startup".
//
// state is package-global (like the audio stream cache): there is exactly
// one keyboard and one mouse per process, so there is nothing to spawn or
// tear down.
@(private)
State :: struct {
	has_prev: bool,

	keys_down:     #sparse [rl.KeyboardKey]bool,
	keys_pressed:  #sparse [rl.KeyboardKey]bool,
	keys_released: #sparse [rl.KeyboardKey]bool,

	mouse_pos:    rl.Vector2,
	mouse_delta:  rl.Vector2,
	mouse_down:     #sparse [rl.MouseButton]bool,
	mouse_pressed:  #sparse [rl.MouseButton]bool,
	mouse_released: #sparse [rl.MouseButton]bool,

	scroll: f32,

	prev_keys:       #sparse [rl.KeyboardKey]bool,
	prev_mouse_pos:  rl.Vector2,
	prev_mouse_down: #sparse [rl.MouseButton]bool,
}

@(private)
state: State

// action name -> key. empty until the user calls bind().
@(private)
bindings: map[string]rl.KeyboardKey

// recent key presses, stamped with rl.GetTime(), for input buffering.
@(private)
BufferEntry :: struct {
	key:  rl.KeyboardKey,
	time: f64,
}

@(private)
input_buffer: [dynamic]BufferEntry

// read raylib's input once and refresh the snapshot.
@(private)
update_input :: proc(world: ^World) {
	state.prev_keys = state.keys_down
	state.prev_mouse_pos = state.mouse_pos
	state.prev_mouse_down = state.mouse_down

	state.keys_pressed = {}
	state.keys_released = {}
	state.mouse_pressed = {}
	state.mouse_released = {}
	state.mouse_delta = {0, 0}
	state.scroll = 0

	for k in rl.KeyboardKey {
		down := rl.IsKeyDown(k)
		state.keys_down[k] = down
		if state.has_prev {
			if down && !state.prev_keys[k] {
				state.keys_pressed[k] = true
			}
			if !down && state.prev_keys[k] {
				state.keys_released[k] = true
			}
		}
	}

	pos := rl.GetMousePosition()
	state.mouse_pos = pos
	if state.has_prev {
		state.mouse_delta = pos - state.prev_mouse_pos
	}
	for b in rl.MouseButton {
		down := rl.IsMouseButtonDown(b)
		state.mouse_down[b] = down
		if state.has_prev {
			if down && !state.prev_mouse_down[b] {
				state.mouse_pressed[b] = true
			}
			if !down && state.prev_mouse_down[b] {
				state.mouse_released[b] = true
			}
		}
	}
	state.scroll = rl.GetMouseWheelMove()

	now := rl.GetTime()
	for k in rl.KeyboardKey {
		if state.keys_pressed[k] {
			append(&input_buffer, BufferEntry{key = k, time = now})
		}
	}
	write := 0
	for read := 0; read < len(input_buffer); read += 1 {
		if now-input_buffer[read].time <= 1.0 {
			input_buffer[write] = input_buffer[read]
			write += 1
		}
	}
	resize(&input_buffer, write)

	state.has_prev = true
	_ = world
}

// --- query api ---
is_down :: proc(key: rl.KeyboardKey) -> bool {
	return state.keys_down[key]
}
is_pressed :: proc(key: rl.KeyboardKey) -> bool {
	return state.keys_pressed[key]
}
is_released :: proc(key: rl.KeyboardKey) -> bool {
	return state.keys_released[key]
}
mouse_position :: proc() -> rl.Vector2 {
	return state.mouse_pos
}
mouse_delta :: proc() -> rl.Vector2 {
	return state.mouse_delta
}
mouse_down :: proc(button: rl.MouseButton) -> bool {
	return state.mouse_down[button]
}
mouse_pressed :: proc(button: rl.MouseButton) -> bool {
	return state.mouse_pressed[button]
}
mouse_released :: proc(button: rl.MouseButton) -> bool {
	return state.mouse_released[button]
}
mouse_scroll :: proc() -> f32 {
	return state.scroll
}
any_key_down :: proc() -> bool {
	for k in rl.KeyboardKey {
		if state.keys_down[k] {
			return true
		}
	}
	return false
}

// --- action bindings + input buffer ---
bind :: proc(action: string, key: rl.KeyboardKey) {
	bindings[action] = key
}
unbind :: proc(action: string) {
	delete_key(&bindings, action)
}
clear_bindings :: proc() {
	clear(&bindings)
}
action_down :: proc(action: string) -> bool {
	if key, ok := bindings[action]; ok {
		return is_down(key)
	}
	return false
}
action_pressed :: proc(action: string) -> bool {
	if key, ok := bindings[action]; ok {
		return is_pressed(key)
	}
	return false
}
action_released :: proc(action: string) -> bool {
	if key, ok := bindings[action]; ok {
		return is_released(key)
	}
	return false
}
consume_buffered :: proc(action: string, window: f64 = 0.1) -> bool {
	key, ok := bindings[action]
	if !ok {
		return false
	}
	return consume_key_buffered(key, window)
}
consume_any_buffered :: proc(window: f64 = 0.1) -> bool {
	now := rl.GetTime()
	i := len(input_buffer) - 1
	for i >= 0 {
		entry := input_buffer[i]
		if now-entry.time > window {
			ordered_remove(&input_buffer, i)
			i -= 1
			continue
		}
		ordered_remove(&input_buffer, i)
		return true
	}
	return false
}
consume_key_buffered :: proc(key: rl.KeyboardKey, window: f64 = 0.1) -> bool {
	now := rl.GetTime()
	i := len(input_buffer) - 1
	for i >= 0 {
		entry := input_buffer[i]
		if now-entry.time > window {
			ordered_remove(&input_buffer, i)
			i -= 1
			continue
		}
		if entry.key == key {
			ordered_remove(&input_buffer, i)
			return true
		}
		i -= 1
	}
	return false
}
clear_buffer :: proc() {
	clear(&input_buffer)
}

@(private)
shutdown_input :: proc() {
	delete(bindings)
	delete(input_buffer)
	bindings = {}
	input_buffer = {}
	state = {}
}

// wire input polling into the app.
InputPlugin :: proc(app: ^App) {
	state = State{}
	clear(&input_buffer)

	init_system_set(app, "update", "input", before("default"))
	add_system(app, "input", update_input)
	add_system(app, "destroy", shutdown_input)
}
// --- terminal input hooks -------------------------------------------------
// public entry points so out-of-process input sources (the terminal plugin)
// can feed the same global input state the raylib input plugin uses. a frame
// is bracketed by begin_input_frame / end_input_frame; in between, callers
// report keys/buttons/position/scroll. raylib's own InputPlugin does the same
// thing internally, so the two never both run in the same app.

begin_input_frame :: proc() {
	state.prev_keys = state.keys_down
	state.prev_mouse_pos = state.mouse_pos
	state.prev_mouse_down = state.mouse_down

	state.keys_pressed = {}
	state.keys_released = {}
	state.mouse_pressed = {}
	state.mouse_released = {}
	state.mouse_delta = {0, 0}
	state.scroll = 0
}

end_input_frame :: proc() {
	state.has_prev = true
}

set_key_down :: proc(key: rl.KeyboardKey, down: bool) {
	state.keys_down[key] = down
	if down {
		if !state.has_prev || !state.prev_keys[key] {
			state.keys_pressed[key] = true
		}
	} else {
		if state.prev_keys[key] {
			state.keys_released[key] = true
		}
	}
}

set_mouse_position :: proc(pos: rl.Vector2) {
	state.mouse_pos = pos
	if state.has_prev {
		state.mouse_delta = pos - state.prev_mouse_pos
	}
}

set_mouse_button_down :: proc(btn: rl.MouseButton, down: bool) {
	state.mouse_down[btn] = down
	if down {
		if !state.prev_mouse_down[btn] {
			state.mouse_pressed[btn] = true
		}
	} else {
		if state.prev_mouse_down[btn] {
			state.mouse_released[btn] = true
		}
	}
}

add_mouse_scroll :: proc(v: f32) {
	state.scroll += v
}
