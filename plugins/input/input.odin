package input

import "core:fmt"
import rl "vendor:raylib"
import ecs "../../src"

// the microui-free, raylib-backed input snapshot. polled once per frame by
// the plugin's "input" set, which is anchored ahead of "default" in the
// "update" walk, so every user update system reads a fresh, complete frame
// of state — same anchoring trick audio_init uses in "startup".
//
// state is package-global (like the audio stream cache): there is exactly
// one keyboard and one mouse per process, so there is nothing to spawn or
// tear down. no startup/destroy systems are needed.
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

// read raylib's input once and refresh the snapshot. runs in the "input"
// set, ahead of "default", so user systems see this frame's state.
@(private)
update_input :: proc(world: ^ecs.World) {
	// snapshot the previous frame before overwriting anything
	state.prev_keys = state.keys_down
	state.prev_mouse_pos = state.mouse_pos
	state.prev_mouse_down = state.mouse_down

	// per-frame edges reset; held state is rebuilt below
	state.keys_pressed = {}
	state.keys_released = {}
	state.mouse_pressed = {}
	state.mouse_released = {}
	state.mouse_delta = {0, 0}
	state.scroll = 0

	// keyboard
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

	// mouse
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

	// record this frame's fresh presses into the input buffer
	now := rl.GetTime()
	for k in rl.KeyboardKey {
		if state.keys_pressed[k] {
			append(&input_buffer, BufferEntry{key = k, time = now})
		}
	}
	// drop stale entries (compaction, O(n))
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

// --- query api ---------------------------------------------------------

// is the key currently held?
is_down :: proc(key: rl.KeyboardKey) -> bool {
	return state.keys_down[key]
}

// did the key go down this frame? (edge: was up last frame, down now)
is_pressed :: proc(key: rl.KeyboardKey) -> bool {
	return state.keys_pressed[key]
}

// did the key come up this frame?
is_released :: proc(key: rl.KeyboardKey) -> bool {
	return state.keys_released[key]
}

// current mouse position in screen space
mouse_position :: proc() -> rl.Vector2 {
	return state.mouse_pos
}

// movement since the previous frame
mouse_delta :: proc() -> rl.Vector2 {
	return state.mouse_delta
}

// is the mouse button currently held?
mouse_down :: proc(button: rl.MouseButton) -> bool {
	return state.mouse_down[button]
}

// did the button go down this frame?
mouse_pressed :: proc(button: rl.MouseButton) -> bool {
	return state.mouse_pressed[button]
}

// did the button come up this frame?
mouse_released :: proc(button: rl.MouseButton) -> bool {
	return state.mouse_released[button]
}

// scroll wheel delta this frame (positive = up)
mouse_scroll :: proc() -> f32 {
	return state.scroll
}

// --- action bindings + input buffer ------------------------------------
// bind an action name to a key. re-binding replaces the previous key.
bind :: proc(action: string, key: rl.KeyboardKey) {
	bindings[action] = key
}

// remove an action's binding
unbind :: proc(action: string) {
	delete_key(&bindings, action)
}

// drop every binding
clear_bindings :: proc() {
	clear(&bindings)
}

// is the bound key currently held?
action_down :: proc(action: string) -> bool {
	if key, ok := bindings[action]; ok {
		return is_down(key)
	}
	return false
}

// did the bound key go down this frame?
action_pressed :: proc(action: string) -> bool {
	if key, ok := bindings[action]; ok {
		return is_pressed(key)
	}
	return false
}

// did the bound key come up this frame?
action_released :: proc(action: string) -> bool {
	if key, ok := bindings[action]; ok {
		return is_released(key)
	}
	return false
}

// input buffer: every key press is stamped with rl.GetTime() and kept for
// a short window, so a press that lands a few frames before the game can
// act on it (jump buffering, coyote time) is not lost. consume removes the
// matching entry so it can't fire twice.

// was `action`'s bound key pressed within `window` seconds? consumes it.
consume_buffered :: proc(action: string, window: f64 = 0.1) -> bool {
	key, ok := bindings[action]
	if !ok {
		return false
	}
	return consume_key_buffered(key, window)
}

// was any key pressed within `window` seconds? consumes the first match.
consume_any_buffered :: proc(window: f64 = 0.1) -> bool {
	now := rl.GetTime()
	// iterate newest-first so the most recent press wins; drop expired
	// entries we pass over
	i := len(input_buffer) - 1
	for i >= 0 {
		entry := input_buffer[i]
		if now-entry.time > window {
			// expired: prune
			ordered_remove(&input_buffer, i)
			i -= 1
			continue
		}
		// first (newest) in-window entry consumes
		ordered_remove(&input_buffer, i)
		return true
	}
	return false
}

// raw-key variant, for callers that don't use action names
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

// drop buffered presses (e.g. on respawn / state change)
clear_buffer :: proc() {
	clear(&input_buffer)
}

// convenience: is any key currently held? (useful for "press any key to continue")
any_key_down :: proc() -> bool {
	for k in rl.KeyboardKey {
		if state.keys_down[k] {
			return true
		}
	}
	return false
}

// free package-global state at teardown (mirrors audio.shutdown)
@(private)
shutdown_input :: proc() {
	delete(bindings)
	delete(input_buffer)
	bindings = {}
	input_buffer = {}
	state = {}
}