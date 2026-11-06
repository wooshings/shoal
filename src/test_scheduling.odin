package shoal


// tests for the scheduling system: name resolution, set ordering, the
// plugin draw pipeline, and system dispatch. run with:
//
//	odin test src -collection:raylib=<odin vendor raylib path>
//
// panic paths are covered separately by tests/panic_probe.odin — Odin has
// no expect-panic test attribute here, so those run as standalone programs
// that the shell expects to exit nonzero.
//
// the runner executes tests on multiple threads by default
// (-define:ODIN_TEST_THREADS); every test here is stateless except one, so
// shared scratch state is only ever touched by a single test.

import "core:testing"

// scratch state shared by the run-log tests
run_log: [dynamic]string
world_captured: ^World

log_reset :: proc() {
	// keep the backing array (appends reuse it), drop the length
	resize(&run_log, 0)
	world_captured = nil
}

// --- procs registered into test apps; names double as log tags ---

p_root :: proc() {
	append(&run_log, "root")
}

p_child :: proc() {
	append(&run_log, "child")
}

p_world :: proc(world: ^World) {
	world_captured = world
	append(&run_log, "world")
}

p_engine :: proc(world: ^World) {
	_ = world
	append(&run_log, "engine")
}

p_user :: proc(world: ^World) {
	_ = world
	append(&run_log, "user")
}

p_bracket_begin :: proc(world: ^World) {
	_ = world
	append(&run_log, "begin")
}

p_bracket_end :: proc() {
	append(&run_log, "end")
}

// assert a root's declared set walk order exactly
expect_set_order :: proc(t: ^testing.T, app: ^App, schedule: string, want: []string) {
	order := get_schedule_set_order(app, schedule)
	if len(order) != len(want) {
		testing.expectf(t, false, "set order for %q: got %v, want %v", schedule, order, want)
		return
	}
	for i := 0; i < len(order); i += 1 {
		if order[i] != want[i] {
			testing.expectf(t, false, "set order for %q at %v: got %q, want %q (full %v vs %v)",
				schedule, i, order[i], want[i], order, want)
			return
		}
	}
}

// assert the run log content exactly
expect_log :: proc(t: ^testing.T, want: []string) {
	if len(run_log) != len(want) {
		testing.expectf(t, false, "run log: got %v, want %v", run_log, want)
		return
	}
	for i := 0; i < len(run_log); i += 1 {
		if run_log[i] != want[i] {
			testing.expectf(t, false, "run log at %v: got %q, want %q (full %v vs %v)",
				i, run_log[i], want[i], run_log, want)
			return
		}
	}
}

// --- resolution ---

@(test)
root_name_targets_default_set :: proc(t: ^testing.T) {
	app: App
	add_system(&app, "update", p_root)
	testing.expect(t, len(get_system(&app, "update", "default")) == 1, "root name -> default set")
	testing.expect(t, len(get_system(&app, "update", "elsewhere")) == 0, "no stray routing")
	expect_set_order(t, &app, "update", []string{"default"})
}

@(test)
child_name_resolves_to_declared_parent :: proc(t: ^testing.T) {
	app: App
	init_system_set(&app, "update", "physics")
	add_system(&app, "physics", p_child)
	testing.expect(t, len(get_system(&app, "update", "physics")) == 1, "child resolves to parent root")
	testing.expect(t, len(get_system(&app, "update", "default")) == 0, "no silent update/default routing")
}

@(test)
root_created_on_first_use :: proc(t: ^testing.T) {
	app: App
	// "destroy" was never declared anywhere — using the root name creates it
	add_system(&app, "destroy", p_root)
	expect_set_order(t, &app, "destroy", []string{"default"})
	testing.expect(t, len(get_system(&app, "destroy", "default")) == 1)
}

@(test)
post_update_is_a_child_of_update :: proc(t: ^testing.T) {
	app: App
	// DefaultPlugin declares "post_update" as a set under "update", anchored
	// after the default set — it is not a root schedule anymore
	DefaultPlugin(&app)
	expect_set_order(t, &app, "update", []string{"default", "post_update"})
	testing.expect(t, len(get_system(&app, "update", "post_update")) == 1, "signal_system lives in update/post_update")
	testing.expect(t, len(get_schedule_set_order(&app, "post_update")) == 0, "no post_update root schedule")
	// the name resolves to its parent root for registration too
	add_system(&app, "post_update", p_root)
	testing.expect(t, len(get_system(&app, "update", "post_update")) == 2)
}

@(test)
world_system_shapes_store_correctly :: proc(t: ^testing.T) {
	app: App
	init_system_set(&app, "update", "m")
	add_system(&app, "m", p_root)   // plain proc()
	add_system(&app, "m", p_world)  // proc(world: ^World)
	systems := get_system(&app, "update", "m")
	testing.expect(t, len(systems) == 2, "both shapes registered")
	testing.expect(t, systems[0].kind == 0, "first is a plain system")
	testing.expect(t, systems[1].kind == 1, "second is a world system")
}

// --- ordering ---

@(test)
anchor_ordering :: proc(t: ^testing.T) {
	app: App
	init_system_set(&app, "update", "mid")
	init_system_set(&app, "update", "last")
	init_system_set(&app, "update", "mid2", before("last"))
	init_system_set(&app, "update", "head", before("missing-anchor")) // falls back to the front
	init_system_set(&app, "update", "tail", after("missing-anchor")) // falls back to the end
	init_system_set(&app, "update", "aftmid", after("mid"))

	expect_set_order(t, &app, "update",
		[]string{"head", "mid", "aftmid", "mid2", "last", "tail"})
}

@(test)
redeclare_under_same_root_is_noop :: proc(t: ^testing.T) {
	app: App
	init_system_set(&app, "update", "x")
	init_system_set(&app, "update", "y")
	init_system_set(&app, "update", "x")
	expect_set_order(t, &app, "update", []string{"x", "y"})
}

// the regression: "default" created implicitly by add_system, then a
// plugin-style anchored declaration must adopt it, not reinsert it
@(test)
implicit_default_is_adopted_not_duplicated :: proc(t: ^testing.T) {
	app: App
	add_system(&app, "draw", p_user) // creates draw's implicit "default"
	init_system_set(&app, "draw", "pre_draw", before("default"))
	init_system_set(&app, "draw", "default", after("pre_draw"))
	add_system(&app, "draw", p_engine)
	init_system_set(&app, "draw", "post_draw")

	expect_set_order(t, &app, "draw", []string{"pre_draw", "default", "post_draw"})
	testing.expect(t, len(get_system(&app, "draw", "default")) == 2, "user + engine systems share the adopted default")
}

// --- the DefaultPlugin draw pipeline (registration shape only — its window
// and drawing systems are never run here) ---

@(test)
default_plugin_pipeline_with_declared_user_sets :: proc(t: ^testing.T) {
	app: App
	init_system_set(&app, "draw", "render")
	init_system_set(&app, "draw", "hud")
	add_system(&app, "render", p_user)
	add_system(&app, "hud", p_root)
	DefaultPlugin(&app)

	expect_set_order(t, &app, "draw",
		[]string{"pre_draw", "default", "render", "hud", "post_draw"})
	testing.expect(t, len(get_system(&app, "draw", "pre_draw")) == 1, "BeginDrawing runs first")
	testing.expect(t, len(get_system(&app, "draw", "default")) == 1, "draw_sprite is the base layer")
	testing.expect(t, len(get_system(&app, "draw", "post_draw")) == 1, "EndDrawing runs last")

	// child resolution keeps working after the plugin ran
	add_system(&app, "render", p_user)
	testing.expect(t, len(get_system(&app, "draw", "render")) == 2, "systems land in the named set")
}

@(test)
default_plugin_pipeline_with_direct_root_draw_system :: proc(t: ^testing.T) {
	app: App
	// a user registering straight on the root before the plugin runs —
	// regression guard for the duplicated-"default" reinsertion bug
	add_system(&app, "draw", p_user)
	DefaultPlugin(&app)

	expect_set_order(t, &app, "draw", []string{"pre_draw", "default", "post_draw"})
	testing.expect(t, len(get_system(&app, "draw", "default")) == 2, "user system + draw_sprite in the default set")
}

@(test)
default_plugin_owns_its_other_roots :: proc(t: ^testing.T) {
	app: App
	// user physics before the plugin — plugin systems must come after it,
	// "post_update" lands inside update (after the default set), and destroy
	// stays its own root, not rerouted
	init_system_set(&app, "update", "physics")
	add_system(&app, "physics", p_user)
	DefaultPlugin(&app)

	expect_set_order(t, &app, "update", []string{"physics", "default", "post_update"})
	testing.expect(t, len(get_schedule_set_order(&app, "post_update")) == 0, "no post_update root")
	expect_set_order(t, &app, "destroy", []string{"default"}) // CloseWindow runs once, after the loop
	expect_set_order(t, &app, "startup", []string{"window"}) // InitWindow runs in the plugin-owned window set
}

// --- execution ---
// NOTE: this is the ONLY test touching run_log/world_captured, so the suite
// stays correct under the test runner's default multi-threaded execution
// (all other tests are stateless and own their own app)

@(test)
system_dispatch_and_execution_order :: proc(t: ^testing.T) {
	log_reset()

	// --- world dispatch first (small, isolated) ---
	app: App
	init_system_set(&app, "update", "m")
	add_system(&app, "m", p_root)
	add_system(&app, "m", p_world)
	run_schedule(&app, "update")
	expect_log(t, []string{"root", "world"})
	testing.expect(t, world_captured == &app.world, "world pointer identity")

	// then a full frame walk, mirroring DefaultPlugin's pipeline layout
	// with test procs so nothing opens a window. "post_update" is a set
	// under "update" now, anchored after the default set like the plugin does
	log_reset()
	frame: App
	init_system_set(&frame, "update", "physics")
	init_system_set(&frame, "draw", "render")
	init_system_set(&frame, "draw", "pre", before("default"))
	init_system_set(&frame, "draw", "default", after("pre"))
	init_system_set(&frame, "draw", "post")
	add_system(&frame, "physics", p_world)
	add_system(&frame, "update", p_root) // update's built-in default set
	init_system_set(&frame, "update", "post_update", after("default"))
	add_system(&frame, "post_update", p_child) // signal-clear stand-in
	add_system(&frame, "pre", p_bracket_begin)
	add_system(&frame, "draw", p_engine)
	add_system(&frame, "render", p_user)
	add_system(&frame, "post", p_bracket_end)

	// the same walk run() does each frame — two schedules, post_update rides
	// inside update
	run_schedule(&frame, "update")
	run_schedule(&frame, "draw")

	expect_log(t, []string{"world", "root", "child", "begin", "engine", "user", "end"})
	testing.expect(t, world_captured == &frame.world, "world systems receive the app's own world")
	// nothing in this synthetic app has touched the plugin's pipeline sets
	testing.expect(t, len(get_system(&frame, "draw", "post_draw")) == 0, "no plugin systems in the synthetic app")
}

@(test)
copy_of_set_order_is_independent :: proc(t: ^testing.T) {
	app: App
	init_system_set(&app, "update", "a")
	order := get_schedule_set_order(&app, "update")
	append(&order, "zzz")
	// mutating the returned copy must not change the engine's walk order
	expect_set_order(t, &app, "update", []string{"a"})
}
