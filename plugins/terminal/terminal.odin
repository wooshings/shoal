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

// raw-mode terminal input state is handled in input.odin.
