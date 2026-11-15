package shoal

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

MAX_LIGHTS :: 4

Light3DKind :: enum { Directional, Point }

Light3D :: struct {
	kind:      Light3DKind,
	direction: rl.Vector3,
	color:     rl.Color,
	intensity: f32,
	radius:    f32,
}

LightCache :: struct {
	kind:      Light3DKind,
	position:  rl.Vector3,
	direction: rl.Vector3,
	color:     rl.Color,
	intensity: f32,
	radius:    f32,
	enabled:   bool,
}

light3d :: proc(
	kind := Light3DKind.Directional,
	direction := rl.Vector3{0, -1, 0},
	color := rl.WHITE,
	intensity: f32 = 1,
	radius: f32 = 12,
) -> Light3D {
	return Light3D{
		kind      = kind,
		direction = direction,
		color     = color,
		intensity = intensity,
		radius    = radius,
	}
}

ambient: rl.Vector4 = {0.18, 0.18, 0.22, 1}

set_ambient :: proc(a: rl.Vector4) {
	ambient = a
}

@(private)
light_shader: rl.Shader

@(private)
shader_ready: bool

@(private)
LightUniforms :: struct {
	enabled:   i32,
	kind:      i32,
	position:  i32,
	direction: i32,
	color:     i32,
	intensity: i32,
	radius:    i32,
}

@(private)
light_uniforms: [MAX_LIGHTS]LightUniforms

@(private)
ambient_loc: i32

@(private)
light_cache: [MAX_LIGHTS]LightCache

@(private)
light_cache_valid: [MAX_LIGHTS]bool

@(private)
ambient_cache: rl.Vector4

@(private)
ambient_cache_valid: bool

@(private)
light_vertex_source :: `
#version 330
in vec3 vertexPosition;
in vec3 vertexNormal;
in vec2 vertexTexCoord;
out vec3 fragPosition;
out vec3 fragNormal;
out vec2 fragTexCoord;
uniform mat4 matModel;
uniform mat4 matNormal;
uniform mat4 mvp;
void main() {
    fragPosition = vec4(matModel * vec4(vertexPosition, 1.0)).xyz;
    fragNormal = vec3(matNormal * vec4(vertexNormal, 1.0));
    fragTexCoord = vertexTexCoord;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

@(private)
light_fragment_source :: `
#version 330
in vec3 fragPosition;
in vec3 fragNormal;
in vec2 fragTexCoord;
out vec4 finalColor;
#define MAX_LIGHTS 4
struct Light {
    int   enabled;
    int   type;
    vec3  position;
    vec3  direction;
    vec4  color;
    float intensity;
    float radius;
};
uniform Light lights[MAX_LIGHTS];
uniform vec4 colDiffuse;
uniform vec4 ambient;
uniform sampler2D texture0;

void main() {
    vec3 normal = normalize(fragNormal);
    vec3 lighting = ambient.rgb;
    for (int i = 0; i < MAX_LIGHTS; i++) {
        if (lights[i].enabled == 1) {
            vec3 lightDir;
            float att = 1.0;
            if (lights[i].type == 0) {
                lightDir = -lights[i].direction;
            } else {
                vec3 toFrag = lights[i].position - fragPosition;
                float dist = max(length(toFrag), 0.0001);
                lightDir = toFrag / dist;
                float t = clamp(1.0 - dist / max(lights[i].radius, 0.001), 0.0, 1.0);
                att = t * t;
            }
            float diff = max(dot(normal, lightDir), 0.0);
            lighting += lights[i].color.rgb * (diff * lights[i].intensity * att);
        }
    }
    vec4 texColor = texture(texture0, fragTexCoord);
    finalColor = vec4(colDiffuse.rgb * texColor.rgb * min(lighting, vec3(1.0)), colDiffuse.a * texColor.a);
}
`

@(private)
init_lighting_shader :: proc() {
	light_shader = rl.LoadShaderFromMemory(
		strings.clone_to_cstring(light_vertex_source, context.temp_allocator),
		strings.clone_to_cstring(light_fragment_source, context.temp_allocator),
	)
	for i in 0 ..< MAX_LIGHTS {
		light_uniforms[i].enabled = rl.GetShaderLocation(
			light_shader,
			strings.clone_to_cstring(fmt.tprintf("lights[%d].enabled", i), context.temp_allocator),
		)
		light_uniforms[i].kind = rl.GetShaderLocation(
			light_shader,
			strings.clone_to_cstring(fmt.tprintf("lights[%d].type", i), context.temp_allocator),
		)
		light_uniforms[i].position = rl.GetShaderLocation(
			light_shader,
			strings.clone_to_cstring(fmt.tprintf("lights[%d].position", i), context.temp_allocator),
		)
		light_uniforms[i].direction = rl.GetShaderLocation(
			light_shader,
			strings.clone_to_cstring(fmt.tprintf("lights[%d].direction", i), context.temp_allocator),
		)
		light_uniforms[i].color = rl.GetShaderLocation(
			light_shader,
			strings.clone_to_cstring(fmt.tprintf("lights[%d].color", i), context.temp_allocator),
		)
		light_uniforms[i].intensity = rl.GetShaderLocation(
			light_shader,
			strings.clone_to_cstring(fmt.tprintf("lights[%d].intensity", i), context.temp_allocator),
		)
		light_uniforms[i].radius = rl.GetShaderLocation(
			light_shader,
			strings.clone_to_cstring(fmt.tprintf("lights[%d].radius", i), context.temp_allocator),
		)
	}
	if light_shader.id == 0 {
		return
	}
	ambient_loc = rl.GetShaderLocation(light_shader, "ambient")
	shader_ready = true
}

@(private)
unload_lighting :: proc() {
	if shader_ready {
		rl.UnloadShader(light_shader)
		shader_ready = false

		for i in 0 ..< MAX_LIGHTS {
			light_uniforms[i].enabled = -1
			light_uniforms[i].kind = -1
			light_uniforms[i].position = -1
			light_uniforms[i].direction = -1
			light_uniforms[i].color = -1
			light_uniforms[i].intensity = -1
			light_uniforms[i].radius = -1
		}
		ambient_loc = -1
	}
}

@(private)
light_cache_equal :: proc(a, b: LightCache) -> bool {
	return a.kind == b.kind &&
		a.position.x == b.position.x &&
		a.position.y == b.position.y &&
		a.position.z == b.position.z &&
		a.direction.x == b.direction.x &&
		a.direction.y == b.direction.y &&
		a.direction.z == b.direction.z &&
		a.color.r == b.color.r &&
		a.color.g == b.color.g &&
		a.color.b == b.color.b &&
		a.color.a == b.color.a &&
		a.intensity == b.intensity &&
		a.radius == b.radius &&
		a.enabled == b.enabled
}

@(private)
reset_light_cache :: proc() {
	for i in 0 ..< MAX_LIGHTS {
		light_cache_valid[i] = false
	}
	ambient_cache_valid = false
}

@(private)
update_lighting :: proc(world: ^World) {
	if !rl.IsWindowReady() {
		return
	}
	if !shader_ready {
		init_lighting_shader()
		if shader_ready {
			reset_light_cache()
		}
	}
	if !shader_ready {
		return
	}

	lights := slice(world, Light3D)
	if len(lights) == 0 {
		sun := spawn_entity(world)
		add_component(
			world,
			sun,
			light3d(.Directional, direction = rl.Vector3Normalize(rl.Vector3{-0.5, -1.0, -0.35})),
		)
		lights = slice(world, Light3D)
	}
	light_entities := slice_entity(world, Light3D)

	for &m in slice(world, Model) {
		if m.model.materials[0].shader.id != light_shader.id {
			m.model.materials[0].shader = light_shader
		}
	}

	for i in 0 ..< MAX_LIGHTS {
		u := &light_uniforms[i]
		cur: LightCache
		if i < len(lights) {
			cur.enabled = true
			cur.kind = lights[i].kind
			pos := rl.Vector3{}
			if t, ok := try_get_component(world, light_entities[i], Transform3D); ok {
				pos = t.translation
			}
			cur.position = pos
			cur.direction = rl.Vector3Normalize(lights[i].direction)
			cur.color = lights[i].color
			cur.intensity = lights[i].intensity
			cur.radius = lights[i].radius
		} else {
			cur.enabled = false
		}
		if !light_cache_valid[i] || !light_cache_equal(cur, light_cache[i]) {
			if i < len(lights) {
				upload_light(light_shader, u, world, light_entities[i], &lights[i])
			} else if u.enabled >= 0 {
				disabled: [1]i32 = {0}
				rl.SetShaderValue(light_shader, u.enabled, &disabled, rl.ShaderUniformDataType.INT)
			}
			light_cache[i] = cur
			light_cache_valid[i] = true
		}
	}

	if !ambient_cache_valid || ambient != ambient_cache {
		if ambient_loc >= 0 {
			rl.SetShaderValue(light_shader, ambient_loc, &ambient, rl.ShaderUniformDataType.VEC4)
		}
		ambient_cache = ambient
		ambient_cache_valid = true
	}
}

@(private)
upload_light :: proc(
	shader: rl.Shader,
	u: ^LightUniforms,
	world: ^World,
	entity: Entity,
	l: ^Light3D,
) {
	position := rl.Vector3{}
	if t, ok := try_get_component(world, entity, Transform3D); ok {
		position = t.translation
	}
	direction := rl.Vector3Normalize(l.direction)

	color := rl.Vector4{
		f32(l.color.r) / 255,
		f32(l.color.g) / 255,
		f32(l.color.b) / 255,
		f32(l.color.a) / 255,
	}

	if u.enabled >= 0 {
		enabled: [1]i32 = {1}
		rl.SetShaderValue(shader, u.enabled, &enabled, rl.ShaderUniformDataType.INT)
	}
	if u.kind >= 0 {
		kind: [1]i32 = {i32(l.kind)}
		rl.SetShaderValue(shader, u.kind, &kind, rl.ShaderUniformDataType.INT)
	}
	if u.position >= 0 {
		rl.SetShaderValue(shader, u.position, &position, rl.ShaderUniformDataType.VEC3)
	}
	if u.direction >= 0 {
		rl.SetShaderValue(shader, u.direction, &direction, rl.ShaderUniformDataType.VEC3)
	}
	if u.color >= 0 {
		rl.SetShaderValue(shader, u.color, &color, rl.ShaderUniformDataType.VEC4)
	}
	if u.intensity >= 0 {
		intensity: [1]f32 = {l.intensity}
		rl.SetShaderValue(shader, u.intensity, &intensity, rl.ShaderUniformDataType.FLOAT)
	}
	if u.radius >= 0 {
		radius: [1]f32 = {l.radius}
		rl.SetShaderValue(shader, u.radius, &radius, rl.ShaderUniformDataType.FLOAT)
	}
}

Light3DPlugin :: proc(app: ^App) {

	init_system_set(app, "draw", "lighting", before("default"))
	add_system(app, "lighting", update_lighting)

	init_system_set(app, "destroy", "lighting_unload", before("default"))
	add_system(app, "lighting_unload", unload_lighting)
}
