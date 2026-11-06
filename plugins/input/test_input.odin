package input

// tests for the input plugin. run with:
//
//	odin test plugins/input -collection:raylib=<odin vendor raylib path>
//
// these tests touch the package-global input state (state, bindings,
// input_buffer), so they are NOT safe under the runner's default
// multi-threaded execution — run with -define:ODIN_TEST_THREADS=1, the same
// caveat as shoal's audio lifecycle test.

import "core:testing"
import rl "vendor:raylib"
import ecs "../../src"

@(test)
first_frame_has_no_edges :: proc(t: ^testing.T) {
	defer shutdown_input()
	world: ecs.World
	state = State{}
	clear(&input_buffer)
	clear(&bindings)

	update_input(&world)

	for k in rl.KeyboardKey {
		testing.expect(t, !state.keys_pressed[k], "no pressed edge on first frame")
		testing.expect(t, !state.keys_released[k], "no released edge on first frame")
	}
	testing.expect(t, state.has_prev, "has_prev set after first poll")
}

@(test)
consume_removes_entry :: proc(t: ^testing.T) {
	defer shutdown_input()
	clear(&input_buffer)
	append(&input_buffer, BufferEntry{key = rl.KeyboardKey.SPACE, time = rl.GetTime()})

	ok := consume_key_buffered(rl.KeyboardKey.SPACE, 1.0)
	testing.expect(t, ok, "first consume succeeds")
	ok2 := consume_key_buffered(rl.KeyboardKey.SPACE, 1.0)
	testing.expect(t, !ok2, "second consume fails (entry removed)")
	testing.expect(t, len(input_buffer) == 0, "buffer empty after consume")
}

@(test)
consume_prefers_newest :: proc(t: ^testing.T) {
	defer shutdown_input()
	clear(&input_buffer)
	now := rl.GetTime()
	append(&input_buffer, BufferEntry{key = rl.KeyboardKey.SPACE, time = now - 0.05})
	append(&input_buffer, BufferEntry{key = rl.KeyboardKey.SPACE, time = now})

	ok := consume_key_buffered(rl.KeyboardKey.SPACE, 0.1)
	testing.expect(t, ok, "consume succeeds")
	// the older entry should remain (newest consumed)
	testing.expect(t, len(input_buffer) == 1, "older entry remains")
}

@(test)
consume_expired_returns_false :: proc(t: ^testing.T) {
	defer shutdown_input()
	clear(&input_buffer)
	append(&input_buffer, BufferEntry{key = rl.KeyboardKey.A, time = rl.GetTime() - 10.0})

	ok := consume_key_buffered(rl.KeyboardKey.A, 0.1)
	testing.expect(t, !ok, "expired entry not consumed")
}

@(test)
consume_any_buffered_works :: proc(t: ^testing.T) {
	defer shutdown_input()
	clear(&input_buffer)
	append(&input_buffer, BufferEntry{key = rl.KeyboardKey.A, time = rl.GetTime()})

	ok := consume_any_buffered(1.0)
	testing.expect(t, ok, "consume any succeeds")
	ok2 := consume_any_buffered(1.0)
	testing.expect(t, !ok2, "buffer empty after consume")
}

@(test)
action_binding_round_trip :: proc(t: ^testing.T) {
	defer shutdown_input()
	clear(&bindings)
	bind("jump", rl.KeyboardKey.SPACE)
	testing.expect(t, action_down("jump") == is_down(rl.KeyboardKey.SPACE), "action_down mirrors key")
	testing.expect(t, !action_pressed("missing"), "unknown action false")
	unbind("jump")
	testing.expect(t, !action_down("jump"), "unbound action false")
}

@(test)
clear_buffer_empties :: proc(t: ^testing.T) {
	defer shutdown_input()
	clear(&input_buffer)
	append(&input_buffer, BufferEntry{key = rl.KeyboardKey.A, time = rl.GetTime()})
	clear_buffer()
	testing.expect(t, len(input_buffer) == 0, "buffer cleared")
}

@(test)
shutdown_frees_state :: proc(t: ^testing.T) {
	bind("x", rl.KeyboardKey.X)
	append(&input_buffer, BufferEntry{key = rl.KeyboardKey.X, time = 0})
	shutdown_input()
	testing.expect(t, len(bindings) == 0, "bindings cleared")
	testing.expect(t, len(input_buffer) == 0, "buffer cleared")
	// leave clean state for other tests
	state = State{}
}