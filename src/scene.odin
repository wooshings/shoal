package shoal

import "core:fmt"

Scene_System :: struct {
	schedule: string,
	set:      string,
	system:   System,
}

Scene :: struct {
	name:    string,
	systems: [dynamic]Scene_System,
}

scenes: map[string]Scene
active_scene: string = ""

ScenePlugin :: proc(app: ^App) {
	if scenes == nil {scenes = map[string]Scene{}}
}

@(private) create_scene :: proc(name: string) {
	if scenes == nil {scenes = map[string]Scene{}}
	if _, ok := scenes[name]; ok {return}
	scenes[name] = Scene{name = name}
}

destroy_scene :: proc(name: string) {
	if scenes == nil {return}
	delete_key(&scenes, name)
	if active_scene == name {active_scene = ""}
}

activate_scene :: proc(name: string) {
	if _, ok := scenes[name]; !ok {
		panic(fmt.tprintf("activate_scene: unknown scene %q", name))
	}
	active_scene = name
}

active_scene_name :: proc() -> string {
	return active_scene
}

Scene_Builder :: struct {
	app:   ^App,
	scene: string,
}

scene :: proc(app: ^App, name: string, block: proc(b: ^Scene_Builder)) {
	create_scene(name)
	b := Scene_Builder{app = app, scene = name}
	block(&b)
}

scene_add :: proc { scene_add_plain, scene_add_world }

scene_add_plain :: proc(b: ^Scene_Builder, schedule: string, system: proc()) {
	add_scene_system(b.app, b.scene, schedule, system)
}

scene_add_world :: proc(b: ^Scene_Builder, schedule: string, system: proc(^World)) {
	add_scene_system(b.app, b.scene, schedule, system)
}

add_scene_system :: proc { add_scene_plain_system, add_scene_world_system }

add_scene_plain_system :: proc(app: ^App, scene, schedule: string, system: proc()) {
	root, set := resolve_schedule(app, schedule)
	create_scene(scene)
	s := scenes[scene]
	append(&s.systems, Scene_System{root, set, System{kind = 0, proc_run = system}})
	scenes[scene] = s
}

add_scene_world_system :: proc(app: ^App, scene, schedule: string, system: proc(^World)) {
	root, set := resolve_schedule(app, schedule)
	create_scene(scene)
	s := scenes[scene]
	append(&s.systems, Scene_System{root, set, System{kind = 1, proc_run_world = system}})
	scenes[scene] = s
}

run_scene_systems :: proc(app: ^App, schedule: string, set: string) {
	if active_scene == "" {return}
	s, ok := scenes[active_scene]
	if !ok {return}
	for ss in s.systems {
		if ss.schedule == schedule && ss.set == set {
			run_system(app, ss.system)
		}
	}
}
