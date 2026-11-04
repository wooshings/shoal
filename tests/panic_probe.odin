package main

// standalone probes for the scheduling system's fail-fast paths. each case
// is expected to panic — the wrapper script checks the exit code is nonzero
// and the output mentions the panic. run per case:
//
//	panic_probe <case>
//
// cases: undeclared_child, unknown_root, root_name_as_set, empty_set,
// cross_root_dup, post_update_root

import "core:fmt"
import "core:os"
import ecs "../src"

app: ecs.App

nop :: proc() {}

main :: proc() {
	args := os.args
	if len(args) < 2 {
		fmt.println("usage: panic_probe <case>")
		os.exit(2)
	}

	switch args[1] {
	case "undeclared_child":
		// add_system against a never-declared, non-root schedule
		ecs.add_system(&app, "physics", nop)
	case "unknown_root":
		// init_system_set against a schedule that isn't one of the roots
		ecs.init_system_set(&app, "frame", "x")
	case "root_name_as_set":
		// a set can't shadow a root schedule's name
		ecs.init_system_set(&app, "update", "update")
	case "empty_set":
		ecs.init_system_set(&app, "update", "")
	case "cross_root_dup":
		// the same set name declared under two roots is ambiguous
		ecs.init_system_set(&app, "update", "x")
		ecs.init_system_set(&app, "draw", "x")
	case "post_update_root":
		// "post_update" is a set under "update" now, not a root schedule
		ecs.init_system_set(&app, "post_update", "x")
	case:
		fmt.println("probe: unknown case", args[1])
		os.exit(2)
	}

	// reaching here means nothing panicked — that's a test failure
	fmt.println("probe: NO PANIC for", args[1])
	os.exit(0)
}
