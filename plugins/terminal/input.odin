package terminal

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:unicode/utf8"
import posix "core:sys/posix"
import rl "vendor:raylib"
import ecs "../../src"

@(private)
stdin_fd :: posix.FD(0)

@(private)
orig_termios: posix.termios

@(private)
have_orig: bool

@(private)
raw_enabled: bool

terminal_enable_raw_mode :: proc() {
	if posix.tcgetattr(stdin_fd, &orig_termios) != .OK {
		return
	}
	have_orig = true
	raw := orig_termios
	raw.c_lflag -= posix.CLocal_Flags{.ICANON, .ECHO, .ECHOE, .ECHOK, .ECHONL, .ISIG}
	raw.c_cc[.VMIN] = 0
	raw.c_cc[.VTIME] = 0
	if posix.tcsetattr(stdin_fd, posix.TC_Optional_Action.TCSAFLUSH, &raw) == .OK {
		raw_enabled = true
	}
}

terminal_disable_raw_mode :: proc() {
	if have_orig {
		posix.tcsetattr(stdin_fd, posix.TC_Optional_Action.TCSAFLUSH, &orig_termios)
		have_orig = false
		raw_enabled = false
	}
}

terminal_enable_mouse :: proc() {
	fmt.print("\x1b[?1000h\x1b[?1006h")
}

terminal_disable_mouse :: proc() {
	fmt.print("\x1b[?1006l\x1b[?1000l")
}

terminal_poll_input :: proc(world: ^ecs.World) {
	ecs.begin_input_frame()

	if !raw_enabled {
		ecs.end_input_frame()
		return
	}

	buf: [4096]u8
	n, err := os.read(os.stdin, buf[:])
	if err != nil || n <= 0 {
		ecs.end_input_frame()
		return
	}
	data := buf[:n]

	i := 0
	for i < len(data) {
		b := data[i]
		if b == 0x1b {
			if i+1 < len(data) && data[i+1] == '[' {
				j := i + 2
				start := j
				for j < len(data) && data[j] >= 0x20 && data[j] <= 0x3f {
					j += 1
				}
				params := string(data[start:j])
				if j < len(data) {
					final := data[j]
					j += 1
					if final == 'M' || final == 'm' {
						if len(params) > 0 && params[0] == '<' {
							parts := split_params(params[1:])
							if len(parts) >= 3 {
								btn, _ := strconv.parse_int(parts[0])
								x, _ := strconv.parse_int(parts[1])
								y, _ := strconv.parse_int(parts[2])
								ecs.set_mouse_position(rl.Vector2{f32(x), f32(y)})
								mb := rl.MouseButton.LEFT
								switch btn & 3 {
								case 1: mb = .MIDDLE
								case 2: mb = .RIGHT
								}
								down := final == 'M'
								if btn >= 64 {
									if btn == 64 { ecs.add_mouse_scroll(1) }
									if btn == 65 { ecs.add_mouse_scroll(-1) }
								} else {
									ecs.set_mouse_button_down(mb, down)
								}
							}
						}
					} else {
						key := csi_to_key(params, final)
						if key != rl.KeyboardKey.KEY_NULL {
							ecs.set_key_down(key, true)
						}
					}
					i = j
				} else {
					i += 1
				}
			} else {
				ecs.set_key_down(rl.KeyboardKey.ESCAPE, true)
				i += 1
			}
		} else {
			r, size := utf8.decode_rune_in_bytes(data[i:])
			if size == 0 { size = 1 }
			if r == '\r' || r == '\n' {
				ecs.set_key_down(rl.KeyboardKey.ENTER, true)
			} else if r == 127 || r == 8 {
				ecs.set_key_down(rl.KeyboardKey.BACKSPACE, true)
			} else if r == 9 {
				ecs.set_key_down(rl.KeyboardKey.TAB, true)
			} else if r >= 32 {
				k := rune_to_key(r)
				if k != rl.KeyboardKey.KEY_NULL {
					ecs.set_key_down(k, true)
				}
			}
			i += size
		}
	}

	ecs.end_input_frame()
	_ = world
}

@(private)
csi_to_key :: proc(params: string, final: u8) -> rl.KeyboardKey {
	if final == 'A' { return rl.KeyboardKey.UP }
	if final == 'B' { return rl.KeyboardKey.DOWN }
	if final == 'C' { return rl.KeyboardKey.RIGHT }
	if final == 'D' { return rl.KeyboardKey.LEFT }
	if final == 'H' { return rl.KeyboardKey.HOME }
	if final == 'F' { return rl.KeyboardKey.END }
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
rune_to_key :: proc(r: rune) -> rl.KeyboardKey {
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
