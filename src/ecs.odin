package shoal

import "core:fmt"
import rl "vendor:raylib"

// ScheduleOption controls where init_system_set inserts a child schedule.
// before("foo") inserts before "foo" (or at the front if "foo" doesn't
// exist). after("bar") inserts after "bar" (or at the end if "bar" doesn't
// exist). omitting the option appends at the end.
ScheduleOption :: struct {
	kind:  u8,
	value: string,
}

// marker functions that return a ScheduleOption for use with init_system_set
before :: proc(name: string) -> ScheduleOption {
	return ScheduleOption{0, name}
}

after :: proc(name: string) -> ScheduleOption {
	return ScheduleOption{1, name}
}

// the engine backend: four root schedules ("startup", "update", "draw",
// "destroy"), each holding a map of named child
// schedules (system sets) to lists of systems, a registry of which child
// schedules live under which root, the plugins that run before everything
// else, and the world, holding every entity and component at a lower scope
// than the app itself. only main() and plugins ever see an ^App; systems are
// handed ^World and so structurally can't reach the registration machinery
// (add_system, init_system_set, plugins, run)
App :: struct {
	schedules: map[string]Schedule,
	// child schedule name -> parent root schedule, filled in by
	// init_system_set. add_system walks it to resolve a child by name alone
	sets:    map[string]string,
	plugins: [dynamic]proc(app: ^App),
	world:   World,
}

// one schedule holds a map of named child schedules (system sets) to system
// lists, plus a slice tracking insertion order so run() walks sets in the
// order they were created
Schedule :: struct {
	groups:      map[string][dynamic]System,
	group_order: [dynamic]string,
}

// a system in either shape add_system accepts: a plain proc(), or one that
// takes the world as proc(world: ^World). stored in a struct with both
// fields plus a discriminant so run() can dispatch the right one.
System :: struct {
	kind:       u8,
	proc_run:   proc(),
	proc_run_world: proc(^World),
}

// the five root schedules run() walks
@(private)
is_root_schedule :: proc(name: string) -> bool {
	return name == "startup" || name == "update" ||
		name == "draw" || name == "destroy"
}

// create a root schedule if it doesn't exist yet, then append a system to one
// of its sets (creating the set, at the end of the walk order, if needed).
// shared by every registration path so they all stay consistent
@(private)
push_system :: proc(app: ^App, schedule: string, set: string, system: System) {
	if _, ok := app.schedules[schedule]; !ok {
		app.schedules[schedule] = Schedule{{}, [dynamic]string{}}
	}
	sched := app.schedules[schedule]
	if _, ok := sched.groups[set]; !ok {
		sched.groups[set] = [dynamic]System{}
		// register the set in group_order so run_schedule walks it
		append(&sched.group_order, set)
	}
	append(&sched.groups[set], system)
	app.schedules[schedule] = sched
}

// register a system on a schedule by name. any schedule works: a root
// schedule ("startup", "update", "draw", "destroy") puts the
// system in that root's built-in "default" set, and a child schedule — a set
// declared with init_system_set — automatically resolves to its parent root,
// so `add_system(app, "physics", step)` lands in "physics" under whichever
// root declared it. an undeclared name panics instead of being silently
// misrouted. a system is either a plain proc(), or takes the world as
// proc(world: ^World) when it needs to spawn entities or touch components
add_system :: proc {
	add_plain_system,
	add_world_system,
}

@(private)
add_plain_system :: proc(app: ^App, schedule: string, system: proc()) {
	root, set := resolve_schedule(app, schedule)
	push_system(app, root, set, System{kind = 0, proc_run = system})
}

@(private)
add_world_system :: proc(app: ^App, schedule: string, system: proc(^World)) {
	root, set := resolve_schedule(app, schedule)
	push_system(app, root, set, System{kind = 1, proc_run_world = system})
}

// turn a schedule name into the (root schedule, set) pair run() actually
// walks: a root name means that root's built-in "default" set, a declared
// child name means (its parent root, itself). anything else panics —
// declaring child schedules with init_system_set is what makes them
// resolvable, so typos surface at registration instead of silently running
// on the wrong schedule
@(private)
resolve_schedule :: proc(app: ^App, name: string) -> (root: string, set: string) {
	if is_root_schedule(name) {
		return name, "default"
	}
	if parent, ok := app.sets[name]; ok {
		return parent, name
	}
	panic(fmt.tprintf(
		"add_system: unknown schedule %q — declare it first with init_system_set(app, root_schedule, \"...\"), or use a root name: \"startup\", \"update\", \"draw\", \"destroy\" (a root name addresses that root's built-in \"default\" set)",
		name,
	))
}

// register a plugin: a proc that gets ^App, the one privilege over regular
// systems, which only ever see ^World. a plugin can add_system/
// init_system_set the same way main() would, and reach the game data through
// get_world. run() executes plugins in registration order, once, before the
// "startup" schedule. the systems a plugin adds can be plain proc() or take
// the world, same as any other add_system call
add_plugin :: proc(app: ^App, plugin: proc(app: ^App)) {
	append(&app.plugins, plugin)
}

// declare a child schedule (system set) under a root schedule. only declared
// child names resolve in add_system, and the declaration decides where the
// set sits in the root's walk order:
//
//	init_system_set(app, "update", "physics")
//	    // appends "physics" after the sets declared so far
//
//	init_system_set(app, "update", "physics", before("render"))
//	    // inserts "physics" before "render" (or at the front if "render"
//	    // doesn't exist)
//
//	init_system_set(app, "update", "physics", after("render"))
//	    // inserts "physics" after "render" (or at the end if "render"
//	    // doesn't exist)
//
// redeclaring the same set under the same root is a no-op. set names are
// global — that's what lets add_system resolve them by name alone — so
// declaring the same name under a different root is ambiguous and panics.
// the root must be one of the five root schedules run() walks. the set
// starts empty; add_system fills it
init_system_set :: proc {
	init_system_set_plain,
	init_system_set_ordered,
}

// declare a child schedule, appended after the sets declared so far
@(private)
init_system_set_plain :: proc(app: ^App, schedule: string, set: string) {
	init_system_set_ordered(app, schedule, set, ScheduleOption{2, ""})
}

// declare a child schedule with an explicit position
@(private)
init_system_set_ordered :: proc(app: ^App, schedule: string, set: string, order: ScheduleOption) {
	if !is_root_schedule(schedule) {
		panic(fmt.tprintf(
			"init_system_set: unknown root schedule %q (valid: \"startup\", \"update\", \"draw\", \"destroy\")",
			schedule,
		))
	}
	if set == "" {
		panic("init_system_set: set name cannot be empty")
	}
	if is_root_schedule(set) {
		panic(fmt.tprintf(
			"init_system_set: set name %q collides with a root schedule",
			set,
		))
	}

	// "default" is a per-root built-in: every root gets one on first
	// add_system against it. you may declare it (to position it via
	// before/after anchors) but it's never tracked in the global registry,
	// so a "default" under several roots is never ambiguous
	if set != "default" {
		// set names are global (add_system resolves them by name alone), so
		// a second declaration under a different root is ambiguous — panic
		// rather than guess
		if app.sets == nil {
			app.sets = {}
		}
		if claimed, ok := app.sets[set]; ok {
			if claimed == schedule {
				return
			}
			panic(fmt.tprintf(
				"init_system_set: set %q is already declared under %q; set names are global, pick a new name",
				set, claimed,
			))
		}
	}

	if _, ok := app.schedules[schedule]; !ok {
		app.schedules[schedule] = Schedule{{}, [dynamic]string{}}
	}

	// a set that exists in this root but was never declared — the
	// implicitly created "default", e.g. — is adopted, not reinserted into
	// the walk order (which would make it run twice)
	if _, ok := app.schedules[schedule].groups[set]; ok {
		if set != "default" {
			app.sets[set] = schedule
		}
		return
	}

	// find insertion point based on the ordering option (kind 2 = plain append)
	insert_at: int = len(app.schedules[schedule].group_order)

	switch order.kind {
	case 0:  // before
		if idx, ok := index_of_group(app.schedules[schedule], order.value); ok {
			insert_at = idx
		} else {
			insert_at = 0
		}
	case 1:  // after
		if idx, ok := index_of_group(app.schedules[schedule], order.value); ok {
			insert_at = idx + 1
		}
	}

	// insert into the group_order slice at the calculated position
	schedule_mut := app.schedules[schedule]
	order_slice := schedule_mut.group_order
	new_order := make([dynamic]string, len(order_slice) + 1)
	for i := 0; i < insert_at; i += 1 {
		new_order[i] = order_slice[i]
	}
	new_order[insert_at] = set
	for i := insert_at; i < len(order_slice); i += 1 {
		new_order[i + 1] = order_slice[i]
	}
	schedule_mut.group_order = new_order
	// the backing array it replaced is abandoned by the header swap — free it
	delete(order_slice)
	schedule_mut.groups[set] = [dynamic]System{}
	app.schedules[schedule] = schedule_mut

	// remember the parent so add_system can resolve the set by name
	if set != "default" {
		app.sets[set] = schedule
	}
}

// everything registered in a child schedule, in registration order, or an
// empty list if nothing was added. each entry is a System struct: switch on
// its kind to tell a plain proc() from a proc(world: ^World). this is what
// run() walks each frame
get_system :: proc(app: ^App, schedule: string, set: string) -> [dynamic]System {
	if s, ok := app.schedules[schedule]; ok {
		if systems, ok := s.groups[set]; ok {
			return systems
		}
	}
	return [dynamic]System{}
}

// return a copy of the child schedule names for a root schedule, in insertion
// order.
get_schedule_set_order :: proc(app: ^App, schedule: string) -> [dynamic]string {
	if s, ok := app.schedules[schedule]; ok {
		order := s.group_order
		if len(order) == 0 {
			return [dynamic]string{}
		}
		result := make([dynamic]string, len(order))
		for i := 0; i < len(order); i += 1 {
			result[i] = order[i]
		}
		return result
	}
	return [dynamic]string{}
}

// the world tucked inside the app, the ^App equivalent of the ^World
// systems get handed. plugins use it to spawn entities or add components
// before the frame loop starts; regular systems never need it, run() gives
// them the same world directly
get_world :: proc(app: ^App) -> ^World {
	return &app.world
}

// configure the window the engine opens at startup, instead of taking the
// built-in 800x600 "shoal window". call it before ecs.run() — before or
// after add_plugin, both work, because plugins only execute inside run()
// and DefaultPlugin adopts an existing Window component instead of
// spawning its default over it:
//
//	ecs.window(&app, ecs.Window{width: 1280, height: 720, title: "my game"})
//
// (width, height, and title are consumed once by InitWindow in the
// "startup" walk, so a startup-system change would come too late — but the
// background color stays runtime-configurable, since pre_draw reads it
// from the component every frame)
window :: proc(app: ^App, window_config: Window) {
	world := get_world(app)
	add_component(world, spawn_entity(world), window_config)
}

// run every plugin (in registration order), then the "startup" schedule once,
// then the frame loop: "update" (whose walk ends with the "post_update" set,
// clearing signal buses) -> "draw", over and over until rl.WindowShouldClose()
// says stop, and finally the "destroy" schedule. world systems get handed the
// app's own world, the same one run() is holding. there's no second copy.
//
// each root schedule is walked in the order its child schedules (system sets)
// were created. within each set, systems run in registration order.
run :: proc(app: ^App) {
	for p in app.plugins {
		p(app)
	}

	// run startup systems (plugins may open the window here)
	run_schedule(app, "startup")

	for {
		run_schedule(app, "update")
		run_schedule(app, "draw")
		if rl.WindowShouldClose() {
			break
		}
	}

	run_schedule(app, "destroy")
}

// run one of the five root schedules. systems within each set run in
// registration order, sets are walked in declaration order.
run_schedule :: proc(app: ^App, schedule: string) {
	for set in get_schedule_set_order(app, schedule) {
		for s in get_system(app, schedule, set) {
			run_system(app, s)
		}
	}
}

// hand a stored system its call: a plain one just runs, a world one gets the
// app's world
@(private)
run_system :: proc(app: ^App, system: System) {
	switch system.kind {
	case 0:
		system.proc_run()
	case 1:
		system.proc_run_world(&app.world)
	}
}

// find the position of a set in a schedule's walk order, used by
// init_system_set's before/after anchors; false when the anchor isn't found
index_of_group :: proc(s: Schedule, set: string) -> (int, bool) {
	for i := 0; i < len(s.group_order); i += 1 {
		if s.group_order[i] == set {
			return i, true
		}
	}
	return -1, false
}
