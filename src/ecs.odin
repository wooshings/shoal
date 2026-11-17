package shoal

import "core:fmt"
import rl "vendor:raylib"
import coretime "core:time"

ScheduleOption :: struct {
	kind:  u8,
	value: string,
}

before :: proc(name: string) -> ScheduleOption {
	return ScheduleOption{0, name}
}

after :: proc(name: string) -> ScheduleOption {
	return ScheduleOption{1, name}
}

App :: struct {
	schedules: map[string]Schedule,

	sets:    map[string]string,
	plugins: [dynamic]proc(app: ^App),
	world:   World,
}

Schedule :: struct {
	groups:      map[string][dynamic]System,
	group_order: [dynamic]string,
}

System :: struct {
	kind:           u8,
	proc_run:       proc(),
	proc_run_world: proc(^World),
}

@(private)
is_root_schedule :: proc(name: string) -> bool {
	return name == "startup" || name == "update" ||
		name == "draw" || name == "destroy"
}

@(private)
push_system :: proc(app: ^App, schedule: string, set: string, system: System) {
	if _, ok := app.schedules[schedule]; !ok {
		app.schedules[schedule] = Schedule{{}, [dynamic]string{}}
	}
	sched := app.schedules[schedule]
	if _, ok := sched.groups[set]; !ok {
		sched.groups[set] = [dynamic]System{}

		append(&sched.group_order, set)
	}
	append(&sched.groups[set], system)
	app.schedules[schedule] = sched
}

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

@(private)
resolve_schedule :: proc(app: ^App, name: string) -> (root: string, set: string) {
	if is_root_schedule(name) {
		return name, "default"
	}
	if parent, ok := app.sets[name]; ok {
		return parent, name
	}
	panic(fmt.tprintf(
		"add_system: unknown schedule %q - declare it first with init_system_set(app, root_schedule, \"...\"), or use a root name: \"startup\", \"update\", \"draw\", \"destroy\" (a root name addresses that root's built-in \"default\" set)",
		name,
	))
}

add_plugin :: proc(app: ^App, plugin: proc(app: ^App)) {
	append(&app.plugins, plugin)
}

add_plugins :: proc(app: ^App, plugins: ..proc(app: ^App)) {
	for p in plugins {
		append(&app.plugins, p)
	}
}

init_system_set :: proc {
	init_system_set_plain,
	init_system_set_ordered,
}

@(private)
init_system_set_plain :: proc(app: ^App, schedule: string, set: string) {
	init_system_set_ordered(app, schedule, set, ScheduleOption{2, ""})
}

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

	if set != "default" {

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

	if _, ok := app.schedules[schedule].groups[set]; ok {
		if set != "default" {
			app.sets[set] = schedule
		}
		return
	}

	insert_at: int = len(app.schedules[schedule].group_order)

	switch order.kind {
	case 0:
		if idx, ok := index_of_group(app.schedules[schedule], order.value); ok {
			insert_at = idx
		} else {
			insert_at = 0
		}
	case 1:
		if idx, ok := index_of_group(app.schedules[schedule], order.value); ok {
			insert_at = idx + 1
		}
	}

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

	delete(order_slice)
	schedule_mut.groups[set] = [dynamic]System{}
	app.schedules[schedule] = schedule_mut

	if set != "default" {
		app.sets[set] = schedule
	}
}

get_system :: proc(app: ^App, schedule: string, set: string) -> [dynamic]System {
	if s, ok := app.schedules[schedule]; ok {
		if systems, ok := s.groups[set]; ok {
			return systems
		}
	}
	return [dynamic]System{}
}

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

get_world :: proc(app: ^App) -> ^World {
	return &app.world
}

window :: proc(app: ^App, window_config: Window) {
	world := get_world(app)
	add_component(world, spawn_entity(world), window_config)
}

run :: proc(app: ^App) {
	for p in app.plugins {
		p(app)
	}

	run_schedule(app, "startup")

	for {
		run_schedule(app, "update")
		if len(read(ExitApp)) > 0 { break }
		run_schedule(app, "draw")
		if len(read(ExitApp)) > 0 { break }
		if rl.WindowShouldClose() { break }
	}

	run_schedule(app, "destroy")
}

run_headless :: proc(app: ^App) {
	for p in app.plugins {
		p(app)
	}
	run_schedule(app, "startup")
	for {
		run_schedule(app, "update")
		if len(read(ExitApp)) > 0 { break }
		coretime.sleep(16 * coretime.Millisecond)
	}
}

run_schedule :: proc(app: ^App, schedule: string) {
	for set in get_schedule_set_order(app, schedule) {
		for s in get_system(app, schedule, set) {
			run_system(app, s)
		}
		run_scene_systems(app, schedule, set)
	}
}

@(private)
run_system :: proc(app: ^App, system: System) {
	switch system.kind {
	case 0:
		system.proc_run()
	case 1:
		system.proc_run_world(&app.world)
	}
}

index_of_group :: proc(s: Schedule, set: string) -> (int, bool) {
	for i := 0; i < len(s.group_order); i += 1 {
		if s.group_order[i] == set {
			return i, true
		}
	}
	return -1, false
}
