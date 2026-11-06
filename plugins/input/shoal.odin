package input

import ecs "../../src"

// wires input polling into the app. the "input" set is anchored ahead of
// "default" in "update", so a full frame of state is already in place when
// user update systems read it — regardless of when this plugin is added.
// usage:
//
//	ecs.add_plugin(&app, input.InputPlugin)
//
// then query anywhere:
//
//	if input.is_pressed(input.SPACE) { ... }
//	pos := input.mouse_position()
InputPlugin :: proc(app: ^ecs.App) {
	// reset per-run transient state; bindings are user config and may have
	// been set before run(), so they are left untouched
	state = State{}
	clear(&input_buffer)

	// poll ahead of user update systems, so a full frame of state is in place
	// when they read it — the same anchoring trick audio_init uses in startup.
	// note: sets a user explicitly anchors before "default" run even earlier;
	// input is guaranteed fresh for the common case (systems in the default set)
	ecs.init_system_set(app, "update", "input", ecs.before("default"))
	ecs.add_system(app, "input", update_input)
	ecs.add_system(app, "destroy", shutdown_input)
}