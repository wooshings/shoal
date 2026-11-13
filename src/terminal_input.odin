package shoal

import "core:fmt"
import "core:strconv"
import rl "vendor:raylib"

import "core:os"
import "core:unicode/utf8"
import posix "core:sys/posix"

// terminal input: reads stdin in raw mode and feeds the same global input
// state the rest of the engine uses (ecs.is_pressed, ecs.mouse_position, ...),
// so terminal games can use the standard input API.

@(private)
stdin_fd :: posix.FD(0)

@(private)
orig_termios: posix.termios

@(private)
have_orig: bool

@(private)
raw_enabled: bool

// enable raw mode: no echo, no canonical line buffering, non-blocking reads.
terminal_enable_raw_mode :: proc() {
	if posix.tcgetattr(stdin_fd, &orig_termios) != .OK {
		return
	}
	have_orig = true
	raw := orig_termios
	// disable canonical mode and echo
	raw.c_lflag -= posix.CLocal_Flags{.ICANON, .ECHO, .ECHOE, .ECHOK, .ECHONL, .ISIG}
	// non-blocking: return immediately from read() with 0 bytes
	raw.c_cc[.VMIN] = 0
	raw.c_cc[.VTIME] = 0
	if posix.tcsetattr(stdin_fd, posix.TC_Optional_Action.TCSAFLUSH, &raw) == .OK {
		raw_enabled = true
	}
}

// restore the original terminal settings.
terminal_disable_raw_mode :: proc() {
	if have_orig {
		posix.tcsetattr(stdin_fd, posix.TC_Optional_Action.TCSAFLUSH, &orig_termios)
		have_orig = false
		raw_enabled = false
	}
}

// enable SGR (1006) mouse tracking so we get mouse events as escape seqs.
terminal_enable_mouse :: proc() {
	fmt.print("\x1b[?1000h\x1b[?1006h")
}

terminal_disable_mouse :: proc() {
	fmt.print("\x1b[?1006l\x1b[?1000l")
}

// read whatever is available on stdin right now and fold it into the global
// input state. called once per frame by the terminal plugin's update system.
terminal_poll_input :: proc(world: ^World) {
	// roll prev state
	state.prev_keys = state.keys_down
	state.prev_mouse_pos = state.mouse_pos
	state.prev_mouse_down = state.mouse_down

	state.keys_pressed = {}
	state.keys_released = {}
	state.mouse_pressed = {}
	state.mouse_released = {}
	state.mouse_delta = {0, 0}
	state.scroll = 0

	if !raw_enabled {
		_ = world
		return
	}

	buf: [4096]u8
	n, err := os.read(os.stdin, buf[:])
	if err != nil || n <= 0 {
		state.has_prev = true
		_ = world
		return
	}
	data := buf[:n]

	// parse escape sequences + printable bytes
	i := 0
	for i < len(data) {
		b := data[i]
		if b == 0x1b {
			// escape sequence
			if i+1 < len(data) && data[i+1] == '[' {
				// CSI
				j := i + 2
				// collect params
				start := j
				for j < len(data) && data[j] >= 0x20 && data[j] <= 0x3f {
					j += 1
				}
				params := string(data[start:j])
				if j < len(data) {
					final := data[j]
					j += 1
					// mouse SGR: [ ... M or m
					if final == 'M' || final == 'm' {
						// params like "<btn;x;y"
						if len(params) > 0 && params[0] == '<' {
							parts := split_params(params[1:])
							if len(parts) >= 3 {
								btn, _ := strconv.parse_int(parts[0])
								x, _ := strconv.parse_int(parts[1])
								y, _ := strconv.parse_int(parts[2])
								state.mouse_pos = rl.Vector2{f32(x), f32(y)}
								// buttons: 0 left, 1 middle, 2 right
								mb: rl.MouseButton = .LEFT
								switch btn & 3 {
								case 1: mb = .MIDDLE
								case 2: mb = .RIGHT
								}
								down := final == 'M'
								if btn >= 64 {
									// scroll
									if btn == 64 { state.scroll += 1 }
									if btn == 65 { state.scroll -= 1 }
								} else {
									if down {
										if !state.mouse_down[mb] {
											state.mouse_pressed[mb] = true
										}
										state.mouse_down[mb] = true
									} else {
										if state.mouse_down[mb] {
											state.mouse_released[mb] = true
										}
										state.mouse_down[mb] = false
									}
								}
							}
						}
					} else {
						// arrow keys etc
						key := csi_to_key(params, final)
						if key != rl.KeyboardKey.KEY_NULL {
							mark_key(key)
						}
					}
					i = j
				} else {
					i += 1
				}
			} else {
				// lone ESC
				mark_key(rl.KeyboardKey.ESCAPE)
				i += 1
			}
		} else {
			// decode one rune
			r, size := utf8.decode_rune_in_bytes(data[i:])
			if size == 0 { size = 1 }
			if r == '\r' || r == '\n' {
				mark_key(rl.KeyboardKey.ENTER)
			} else if r == 127 || r == 8 {
				mark_key(rl.KeyboardKey.BACKSPACE)
			} else if r == 9 {
				mark_key(rl.KeyboardKey.TAB)
			} else if r >= 32 {
				// map printable to raylib key if it's a letter
				k := rune_to_raylib_key(r)
				if k != rl.KeyboardKey.KEY_NULL {
					mark_key(k)
				}
				// also store in a side channel? global state only keys; ok
			}
			i += size
		}
	}

	state.has_prev = true
	_ = world
}

@(private)
mark_key :: proc(k: rl.KeyboardKey) {
	state.keys_down[k] = true
	if state.has_prev {
		if !state.prev_keys[k] {
			state.keys_pressed[k] = true
		}
	} else {
		state.keys_pressed[k] = true
	}
}

@(private)
csi_to_key :: proc(params: string, final: u8) -> rl.KeyboardKey {
	if final == 'A' { return rl.KeyboardKey.UP }
	if final == 'B' { return rl.KeyboardKey.DOWN }
	if final == 'C' { return rl.KeyboardKey.RIGHT }
	if final == 'D' { return rl.KeyboardKey.LEFT }
	if final == 'H' { return rl.KeyboardKey.HOME }
	if final == 'F' { return rl.KeyboardKey.END }
	// tilde codes
	if final == '~' {
		switch params {
		case "1": return rl.KeyboardKey.HOME
		case "3": return rl.KeyboardKey.DELETE
		case "4": return rl.KeyboardKey.END
		case "5": return rl.KeyboardKey.PAGE_UP
		case "6": return rl.KeyboardKey.PAGE_DOWN
		}
	}
	return rl.KeyboardKey.KEY_NULL
}

@(private)
rune_to_raylib_key :: proc(r: rune) -> rl.KeyboardKey {
	if r >= 'a' && r <= 'z' {
		return rl.KeyboardKey(r - 'a' + 'A')
	}
	if r >= 'A' && r <= 'Z' {
		return rl.KeyboardKey(r)
	}
	if r >= '0' && r <= '9' {
		return rl.KeyboardKey(r)
	}
	switch r {
	case ' ': return rl.KeyboardKey.SPACE
	}
	return rl.KeyboardKey.KEY_NULL
}

@(private)
split_params :: proc(s: string) -> []string {
	// split on ';'
	res := [dynamic]string{}
	start := 0
	for i := 0; i <= len(s); i += 1 {
		if i == len(s) || s[i] == ';' {
			append(&res, s[start:i])
			start = i + 1
		}
	}
	return res[:]
}
