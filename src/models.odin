package shoal

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// models are cached by path — the path is the handle, same rule as sprites
// and audio: first call loads from disk, every call after returns the same
// model. the cache owns every model and frees them all at "destroy"
models: map[string]rl.Model

// models built in memory by the gen_* procs below have no path key, so they
// live here instead of the cache and are freed at "destroy" too. the list
// grows during play (remote players spawn cubes on the fly) but stays
// bounded by entity count
@(private)
generated_models: [dynamic]rl.Model

// cache lookup or disk load. panics on a path that can't be loaded: raylib
// returns an invalid model on failure and drawing it renders nothing — a
// typo'd asset path would just show blank forever. same fail-fast rule as
// load_sprite and play_sound
@(private)
get_model :: proc(path: string) -> rl.Model {
	if m, ok := models[path]; ok {
		return m
	}
	m := rl.LoadModel(strings.clone_to_cstring(path))
	if !rl.IsModelValid(m) {
		panic(fmt.tprintf("load_model: could not load model %q", path))
	}
	models[path] = m
	return m
}

// free every cached and generated model. registered in its own "models"
// destroy set, ahead of the default set that holds CloseWindow — UnloadModel
// needs the GL context alive
unload_models :: proc() {
	for _, m in models {
		rl.UnloadModel(m)
	}
	delete(models)
	for m in generated_models {
		rl.UnloadModel(m)
	}
	delete(generated_models)
}

// load a 3D model from a file path (.obj, .gltf, .glb, .iqm, ...). returns
// a Model component with the loaded model and a white tint. models are
// cached by path: repeated calls return the same model instead of reloading,
// so spawning a hundred entities from one file costs one load. the cache
// owns the models — there is no per-entity unload; everything is freed at
// "destroy". a path that can't be loaded panics with the path
//
//     model := load_model("models/duck.glb")
//     ecs.add_component(world, entity, model)
load_model :: proc(path: string) -> Model {
	m := get_model(path)
	return model(m)
}

// generate a cuboid model from dimensions, with a default material. handy
// for prototyping without an asset file — the mesh is built in memory and
// wrapped in a Model, so it behaves exactly like a loaded one
//
//     cube := gen_model_cube(1, 1, 1)
//     ecs.add_component(world, entity, cube)
gen_model_cube :: proc(width, height, length: f32) -> Model {
	mesh := rl.GenMeshCube(width, height, length)
	m := rl.LoadModelFromMesh(mesh)
	append(&generated_models, m)
	return model(m)
}

// generate a sphere model from a radius and rings/slices. handy for
// prototyping without an asset file
gen_model_sphere :: proc(radius: f32, rings, slices: i32) -> Model {
	mesh := rl.GenMeshSphere(radius, rings, slices)
	m := rl.LoadModelFromMesh(mesh)
	append(&generated_models, m)
	return model(m)
}

// generate a plane model from its size. handy for floors/ground
gen_model_plane :: proc(width, length: f32) -> Model {
	mesh := rl.GenMeshPlane(width, length, 1, 1)
	m := rl.LoadModelFromMesh(mesh)
	append(&generated_models, m)
	return model(m)
}

// generate a vertical quad (billboard-friendly) of given size, normal +Z.
// built as a GenMeshPlane rotated 90 deg about X so it stands upright;
// the mesh is transformed at generation time, so callers just apply a
// yaw (rotation.y) to face the camera.
gen_model_quad :: proc(width, height: f32) -> Model {
    mesh := rl.GenMeshPlane(width, height, 1, 1)
    // rotate vertices 90 deg about X: (x,y,z) -> (x, -z, y)
    vcount := int(mesh.vertexCount)
    for i in 0 ..< vcount {
        x := mesh.vertices[i*3 + 0]
        y := mesh.vertices[i*3 + 1]
        z := mesh.vertices[i*3 + 2]
        mesh.vertices[i*3 + 0] = x
        mesh.vertices[i*3 + 1] = -z
        mesh.vertices[i*3 + 2] = y
        if mesh.normals != nil {
            nx := mesh.normals[i*3 + 0]
            ny := mesh.normals[i*3 + 1]
            nz := mesh.normals[i*3 + 2]
            mesh.normals[i*3 + 0] = nx
            mesh.normals[i*3 + 1] = -nz
            mesh.normals[i*3 + 2] = ny
        }
    }
    m := rl.LoadModelFromMesh(mesh)
    append(&generated_models, m)
    return model(m)
}

// load a texture for use on a 3D model's material. textures are cached by
// path (same cache as sprites), so repeated calls are free and everything
// is unloaded at "destroy".
load_texture :: proc(path: string) -> rl.Texture2D {
	return get_texture(path)
}

// draw every Model component using DrawModelEx, reading placement from the
// entity's Transform3DComponent. a missing Transform3DComponent is a
// fail-fast panic, like a missing Transform on a sprite entity. transform
// rotation is interpreted as euler radians (pitch, yaw, roll)
@(private)
draw_model :: proc(world: ^World) {
	components := slice(world, Model)
	entities := slice_entity(world, Model)
	for &v, i in components {
		transform := get_component(world, entities[i], Transform3D)

		// build the model's transform matrix from position/rotation/scale.
		// raylib's DrawModelEx takes a rotation axis + angle, but we store
		// euler angles, so build the matrix directly and draw at the origin
		// with unit scale — the matrix carries everything
		m := rl.MatrixTranslate(transform.translation.x, transform.translation.y, transform.translation.z)
		m = m * rl.MatrixRotateXYZ(transform.rotation)
		m = m * rl.MatrixScale(transform.scale.x, transform.scale.y, transform.scale.z)
		v.model.transform = m

		tint := v.tint
		if tint == (rl.Color{}) {
			tint = rl.WHITE
		}
		rl.DrawModel(v.model, rl.Vector3{}, 1.0, tint)
	}
}

// wire 3D model rendering into the app. adds draw_model to the "draw" root's
// default set, so it runs in world space (inside the 3D camera's begin/end
// when Camera3DPlugin is active). also registers model unloading in
// "destroy". add it after DefaultPlugin:
//
//	ecs.add_plugin(&app, ecs.DefaultPlugin)
//	ecs.add_plugin(&app, ecs.ModelPlugin)
ModelPlugin :: proc(app: ^App) {
	add_system(app, "draw", draw_model)
	// the model unload lives in its own "models" set anchored ahead of
	// "default" — DefaultPlugin registers CloseWindow in the destroy
	// default set, and plugin registration (here) lands after it, so an
	// unload appended to default would run with the GL context already
	// gone. same pattern as the ui plugin's "atlas" set
	init_system_set(app, "destroy", "models", before("default"))
	add_system(app, "models", unload_models)
}

// convenience: DefaultPlugin + Camera3DPlugin + ModelPlugin + Light3DPlugin,
// for 3D games that don't need the 2D camera or sprites. the lighting
// shader is stamped onto every model per frame, so models also get the
// engine's default sun when the world has no Light3D component of its own.
// models without the lighting plugin keep drawing unlit — add
// ecs.Light3DPlugin yourself instead of this bundle for that
Default3DPlugin :: proc(app: ^App) {
	DefaultPlugin(app)
	Camera3DPlugin(app)
	ModelPlugin(app)
	Light3DPlugin(app)
}