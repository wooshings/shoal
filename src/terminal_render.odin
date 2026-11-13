package shoal

import "core:fmt"
import "core:strings"

@(private)
startup_terminal :: proc() {
	fmt.print("\x1b[?25l\x1b[2J\x1b[H")
}

@(private)
shutdown_terminal :: proc() {
	fmt.print("\x1b[0m\x1b[?25h\n")
}

@(private)
render_terminal :: proc(world: ^World) {
	width := 80
	height := 24
	if len(slice(world, Terminal)) > 0 {
		t := slice(world, Terminal)[0]
		if t.width > 0 { width = t.width }
		if t.height > 0 { height = t.height }
	}

	grid := make([]terminal_cell, width * height)
	defer delete(grid)
	for i in 0 ..< len(grid) {
		grid[i] = terminal_cell{glyph = ' ', fg = .White, bg = .Black, bold = false}
	}

	chars := slice(world, Character)
	for &ch in chars {
		if ch.y < 0 || ch.y >= height {
			continue
		}
		if ch.text != "" {
			cx := ch.x
			for r in ch.text {
				if cx < 0 || cx >= width {
					cx += 1
					continue
				}
				idx := ch.y * width + cx
				grid[idx].glyph = r
				fg := ch.fg
				if fg == .Black && ch.color != .Black { fg = ch.color }
				grid[idx].fg = fg
				grid[idx].bg = ch.bg
				grid[idx].bold = ch.bold
				cx += 1
			}
		} else {
			if ch.x < 0 || ch.x >= width {
				continue
			}
			g := ch.glyph
			if g == 0 { g = ch.char }
			if g == 0 { g = ch.symbol }
			if g == 0 { g = ch.ch }
			if g == 0 { g = ' ' }
			idx := ch.y * width + ch.x
			grid[idx].glyph = g
			fg := ch.fg
			if fg == .Black && ch.color != .Black { fg = ch.color }
			grid[idx].fg = fg
			grid[idx].bg = ch.bg
			grid[idx].bold = ch.bold
		}
	}

	b := strings.builder_make()
	defer strings.builder_destroy(&b)
	strings.write_string(&b, "\x1b[H")
	for y in 0 ..< height {
		for x in 0 ..< width {
			c := grid[y * width + x]
			if c.bold {
				fmt.sbprintf(&b, "\x1b[1;%d;%dm%c", fg_code(c.fg), bg_code(c.bg), c.glyph)
			} else {
				fmt.sbprintf(&b, "\x1b[%d;%dm%c", fg_code(c.fg), bg_code(c.bg), c.glyph)
			}
		}
		strings.write_string(&b, "\x1b[0m\n")
	}
	fmt.print(strings.to_string(b))
}

@(private)
terminal_cell :: struct {
	glyph: rune,
	fg:    TermColor,
	bg:    TermColor,
	bold:  bool,
}

// wire terminal rendering into the app. add it after HeadlessDefaultPlugin
// (or any plugin that provides the update schedule):
//
//	ecs.add_plugin(&app, ecs.HeadlessDefaultPlugin)
//	ecs.add_plugin(&app, ecs.TerminalPlugin)
//	ecs.run_headless(&app)
TerminalPlugin :: proc(app: ^App) {
	world := get_world(app)
	if len(slice(world, Terminal)) == 0 {
		t := spawn_entity(world)
		add_component(world, t, Terminal{width = 80, height = 24})
	}

	add_system(app, "startup", startup_terminal)
	init_system_set(app, "update", "terminal_render", after("default"))
	add_system(app, "terminal_render", render_terminal)
	add_system(app, "destroy", shutdown_terminal)
}

// aliases for compatibility with other naming conventions
TerminalRenderPlugin :: TerminalPlugin
TerminalRendererPlugin :: TerminalPlugin
