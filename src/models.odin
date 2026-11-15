package shoal

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

models: map[string]rl.Model

@(private)
generated_models: [dynamic]rl.Model

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

load_model :: proc(path: string) -> Model {
	m := get_model(path)
	return model(m)
}

gen_model_cube :: proc(width, height, length: f32) -> Model {
	mesh := rl.GenMeshCube(width, height, length)
	m := rl.LoadModelFromMesh(mesh)
	append(&generated_models, m)
	return model(m)
}

gen_model_sphere :: proc(radius: f32, rings, slices: i32) -> Model {
	mesh := rl.GenMeshSphere(radius, rings, slices)
	m := rl.LoadModelFromMesh(mesh)
	append(&generated_models, m)
	return model(m)
}

gen_model_plane :: proc(width, length: f32) -> Model {
	mesh := rl.GenMeshPlane(width, length, 1, 1)
	m := rl.LoadModelFromMesh(mesh)
	append(&generated_models, m)
	return model(m)
}

gen_model_quad :: proc(width, height: f32) -> Model {
    mesh := rl.GenMeshPlane(width, height, 1, 1)

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

load_texture :: proc(path: string) -> rl.Texture2D {
	return get_texture(path)
}

@(private)
draw_model :: proc(world: ^World) {
	components := slice(world, Model)
	entities := slice_entity(world, Model)
	for &v, i in components {
		transform := get_component(world, entities[i], Transform3D)

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

ModelPlugin :: proc(app: ^App) {
	add_system(app, "draw", draw_model)

	init_system_set(app, "destroy", "models", before("default"))
	add_system(app, "models", unload_models)
}

Default3DPlugin :: proc(app: ^App) {
	DefaultPlugin(app)
	Camera3DPlugin(app)
	ModelPlugin(app)
	Light3DPlugin(app)
}
