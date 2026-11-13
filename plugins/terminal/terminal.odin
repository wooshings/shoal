package terminal

import "core:fmt"
import rl "vendor:raylib"
import ecs "../../src"

// ANSI terminal color palette.
TermColor :: enum {
	Black,
	Red,
	Green,
	Yellow,
	Blue,
	Magenta,
	Cyan,
	White,
	BrightBlack,
	BrightRed,
	BrightGreen,
	BrightYellow,
	BrightBlue,
	BrightMagenta,
	BrightCyan,
	BrightWhite,
}

// a single glyph or a run of text drawn on the terminal grid.
Character :: struct {
	glyph:  rune,
	char:   rune,
	symbol: rune,
	ch:     rune,
	text:   string,
	x:      int,
	y:      int,
	fg:     TermColor,
	bg:     TermColor,
	color:  TermColor,
	bold:   bool,
}

// the terminal screen dimensions.
Terminal :: struct {
	width:  int,
	height: int,
}

// a camera for the terminal renderer. its position (x, y) is the world point
// that lands at the centre of the terminal, and zoom scales world units to
// terminal cells. with no TerminalCamera in the world the renderer draws in
// 1:1 cell space.
TerminalCamera :: struct {
	x:    f32,
	y:    f32,
	zoom: f32,
}

// raw-mode terminal input state is handled in input.odin.
