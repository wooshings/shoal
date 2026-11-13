package terminal

import "core:fmt"
import ecs "../../src"

// ---- immediate-mode UI ----------------------------------------------------

UIItem :: struct {
	x, y:     int,
	text:     string,
	fg, bg:   TermColor,
	bold:     bool,
	is_button: bool,
	id:       string,
	w:        int,
}

@(private)
ui_items: [dynamic]UIItem

@(private)
ui_hot: string

@(private)
ui_active: string

// call once per frame before issuing ui_* calls.
ui_begin :: proc() {
	clear(&ui_items)
	ui_hot = ""
	ui_active = ""
}

// draw a text label at (x, y).
ui_label :: proc(x, y: int, text: string, fg: TermColor = .White) {
	append(&ui_items, UIItem{x = x, y = y, text = text, fg = fg, bg = .Black, bold = false})
}

// draw a button; returns true on the frame it is clicked.
ui_button :: proc(id: string, x, y: int, label: string, fg: TermColor = .White, bg: TermColor = .Magenta) -> bool {
	text := fmt.tprintf("[%s]", label)
	w := len(text)
	append(&ui_items, UIItem{x = x, y = y, text = text, fg = fg, bg = bg, bold = true, is_button = true, id = id, w = w})

	mp := ecs.mouse_position()
	mx := int(mp.x)
	my := int(mp.y)
	hot := mx >= x && mx < x + w && my == y
	clicked := false
	if hot {
		ui_hot = id
		if ecs.mouse_pressed(ecs.MB_LEFT) {
			ui_active = id
			clicked = true
		}
	}
	return clicked
}

// draw a bordered box (just a label-style placeholder for now).
ui_box :: proc(x, y, w, h: int, title: string = "") {
	if title != "" {
		ui_label(x + 1, y, title, .Cyan)
	}
}

// whether the given id is currently hot (under the mouse).
ui_is_hot :: proc(id: string) -> bool {
	return ui_hot == id
}

// whether the given id is currently active (being clicked).
ui_is_active :: proc(id: string) -> bool {
	return ui_active == id
}
