package shoal

// --- terminal rendering (used by the terminal render plugin) ---
//
// a small set of components for terminal-based games (roguelikes and the
// like). the terminal render plugin (plugins/terminal) consumes them; they
// live here so callers can refer to them as ecs.Character, ecs.Terminal, etc.

// ANSI terminal color palette. maps to the standard 16-color set so it works
// in any terminal that supports ANSI escapes.
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

// a single glyph placed on the terminal grid. the terminal render plugin
// collects every Character component in the world each frame and draws it.
Character :: struct {
	glyph: rune,
	x:     int,
	y:     int,
	fg:    TermColor,
	bg:    TermColor,
	bold:  bool,
}

// the terminal screen: its cell grid dimensions. the plugin spawns one of
// these if main() didn't configure one, defaulting to 80x24.
Terminal :: struct {
	width:  int,
	height: int,
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
	return fg_code(c) + 10
}
