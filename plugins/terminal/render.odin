package terminal

import "core:fmt"
import "core:strings"
import ecs "../../src"

@(private)
winsize :: struct {
	ws_row:    u16,
	ws_col:    u16,
	ws_xpixel: u16,
	ws_ypixel: u16,
}

foreign import libc "system:c"

foreign libc {
	ioctl :: proc(fd: i32, request: u64, arg: rawptr) -> i32 ---
}

TIOCGWINSZ :: u64(0x40087468)

@(private)
terminal_get_size :: proc() -> (int, int) {
	ws: winsize
	if ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0 && ws.ws_row > 0 {
		return int(ws.ws_col), int(ws.ws_row)
	}
	return 0, 0
}

@(private)
fg_code :: proc(c: TermColor) -> int {
	switch c {
	case .Black:         return 30
	case .Red:           return 31
	case .Green:         return 32
	case .Yellow:        return 33
	case .Blue:          return 34
	case .Magenta:       return 35
	case .Cyan:          return 36
	case .White:         return 37
	case .BrightBlack:   return 90
	case .BrightRed:     return 91
	case .BrightGreen:   return 92
	case .BrightYellow:  return 93
	case .BrightBlue:    return 94
	case .BrightMagenta: return 95
	case .BrightCyan:    return 96
	case .BrightWhite:   return 97
	}
	return 37
}

@(private)
bg_code :: proc(c: TermColor) -> int {
	// paint "black" as the terminal's default background (49), not ANSI
	// black (40) — ANSI black is a theme gray that leaves visible patches
	// over the emulator's real background color
	if c == .Black { return 49 }
	return fg_code(c) + 10
}

@(private)
cell :: struct {
	glyph: rune,
	fg:    TermColor,
	bg:    TermColor,
	bold:  bool,
}

// persistent frame buffers for differential rendering: only changed cells
// are ever written to the terminal, so idle frames cost zero bytes over ssh
@(private)
rt_grid:    []cell
@(private)
rt_prev:    []cell
@(private)
rt_w, rt_h: int
@(private)
rt_started: bool

@(private)
startup_terminal :: proc() {
	terminal_enable_raw_mode()
	terminal_enable_mouse()
	fmt.print("\x1b[?25l\x1b[2J\x1b[H")
}

@(private)
shutdown_terminal :: proc() {
	terminal_disable_mouse()
	terminal_disable_raw_mode()
	fmt.print("\x1b[0m\x1b[?25h\n")
}

@(private)
render_terminal :: proc(world: ^ecs.World) {
	width, height := terminal_get_size()
	if width == 0 || height == 0 {
		width = 80
		height = 24
		if len(ecs.slice(world, Terminal)) > 0 {
			t := ecs.slice(world, Terminal)[0]
			if t.width > 0 { width = t.width }
			if t.height > 0 { height = t.height }
		}
	}

	// (re)allocate the persistent frame buffers on terminal resize
	if rt_w != width || rt_h != height || len(rt_grid) != width*height {
		if len(rt_grid) > 0 {
			delete(rt_grid)
			delete(rt_prev)
		}
		rt_w, rt_h = width, height
		rt_grid = make([]cell, width*height)
		rt_prev = make([]cell, width*height)
	}
	grid := rt_grid
	for i in 0 ..< len(grid) {
		grid[i] = cell{glyph = ' ', fg = .White, bg = .Black, bold = false}
	}

	// resolve camera (if any)
	cam_x, cam_y, cam_zoom: f32 = 0, 0, 1
	has_cam := false
	if len(ecs.slice(world, TerminalCamera)) > 0 {
		c := ecs.slice(world, TerminalCamera)[0]
		cam_x = c.x
		cam_y = c.y
		if c.zoom != 0 { cam_zoom = c.zoom } else { cam_zoom = 1 }
		has_cam = true
	}

	to_screen :: proc(wx, wy: f32, has_cam: bool, cam_x, cam_y, cam_zoom: f32, tw, th: int) -> (int, int) {
		if has_cam {
			sx := (wx - cam_x) * cam_zoom + f32(tw) * 0.5
			sy := (wy - cam_y) * cam_zoom + f32(th) * 0.5
			return int(sx), int(sy)
		}
		return int(wx), int(wy)
	}

	chars := ecs.slice(world, Character)
	for &ch in chars {
		fg := ch.fg
		if fg == .Black && ch.color != .Black { fg = ch.color }

		if ch.text != "" {
			wx := f32(ch.x)
			wy := f32(ch.y)
			cx := 0
			_ = cx
			ri := 0
			for r in ch.text {
				sx, sy := to_screen(wx + f32(ri), wy, has_cam, cam_x, cam_y, cam_zoom, width, height)
				if sx >= 0 && sx < width && sy >= 0 && sy < height {
					idx := sy * width + sx
					grid[idx].glyph = r
					grid[idx].fg = fg
					grid[idx].bg = ch.bg
					grid[idx].bold = ch.bold
				}
				ri += 1
			}
		} else {
			g := ch.glyph
			if g == 0 { g = ch.char }
			if g == 0 { g = ch.symbol }
			if g == 0 { g = ch.ch }
			if g == 0 { g = ' ' }
			sx, sy := to_screen(f32(ch.x), f32(ch.y), has_cam, cam_x, cam_y, cam_zoom, width, height)
			if sx >= 0 && sx < width && sy >= 0 && sy < height {
				idx := sy * width + sx
				grid[idx].glyph = g
				grid[idx].fg = fg
				grid[idx].bg = ch.bg
				grid[idx].bold = ch.bold
			}
		}
	}

	// stamp immediate-mode UI items on top
	for &it in ui_items {
		cx := it.x
		for r in it.text {
			if cx >= 0 && cx < width && it.y >= 0 && it.y < height {
				idx := it.y * width + cx
				grid[idx].glyph = r
				grid[idx].fg = it.fg
				grid[idx].bg = it.bg
				grid[idx].bold = it.bold
			}
			cx += 1
		}
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)

	// first frame (or after a resize): clear and repaint everything
	full_paint := !rt_started
	if full_paint {
		strings.write_string(&b, "\x1b[2J\x1b[H")
		rt_started = true
	}

	// differential emission: track SGR state + cursor position so consecutive
	// changed cells share one escape sequence
	cur_fg, cur_bg: TermColor = .White, .Black
	cur_bold: bool   = false
	sgr_valid: bool  = false
	cx, cy: int      = -1, -1
	any: bool        = false

	for y in 0 ..< height {
		for x in 0 ..< width {
			i := y*width + x
			c := grid[i]
			p := rt_prev[i]
			if c == p { continue }
			rt_prev[i] = c
			// plain blanks need no paint on a full repaint (screen already dark)
			if full_paint && c.glyph == ' ' && c.fg == .White && c.bg == .Black && !c.bold {
				continue
			}
			if x != cx || y != cy {
				fmt.sbprintf(&b, "\x1b[%d;%dH", y+1, x+1)
			}
			if !sgr_valid || c.bold != cur_bold || c.fg != cur_fg || c.bg != cur_bg {
				if c.bold {
					fmt.sbprintf(&b, "\x1b[0;1;%d;%dm", fg_code(c.fg), bg_code(c.bg))
				} else {
					fmt.sbprintf(&b, "\x1b[0;%d;%dm", fg_code(c.fg), bg_code(c.bg))
				}
				cur_fg, cur_bg, cur_bold, sgr_valid = c.fg, c.bg, c.bold, true
			}
			strings.write_rune(&b, c.glyph)
			cx, cy = x+1, y
			any = true
		}
	}

	// idle frame with no changes: emit nothing at all
	if any {
		fmt.print(strings.to_string(b))
	}
}

TerminalPlugin :: proc(app: ^ecs.App) {
	world := ecs.get_world(app)
	if len(ecs.slice(world, Terminal)) == 0 {
		t := ecs.spawn_entity(world)
		ecs.add_component(world, t, Terminal{width = 80, height = 24})
	}

	ecs.add_system(app, "startup", startup_terminal)
	ecs.init_system_set(app, "update", "terminal_input", ecs.before("default"))
	ecs.add_system(app, "terminal_input", terminal_poll_input)
	ecs.init_system_set(app, "update", "terminal_render", ecs.after("default"))
	ecs.add_system(app, "terminal_render", render_terminal)
	ecs.add_system(app, "destroy", shutdown_terminal)
}

TerminalRenderPlugin :: TerminalPlugin
TerminalRendererPlugin :: TerminalPlugin
