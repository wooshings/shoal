package shoal

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// how many lights the lighting shader can hold at once. MUST match the
// #define MAX_LIGHTS in the fragment shader below — the GLSL uniform array
// is fixed size and the uniform-location cache is sized from this
MAX_LIGHTS :: 4

Light3DKind :: enum { Directional, Point }

// marks its entity as a 3d light. for Point lights the light's position is
// the entity's Transform3DComponent translation (move the light by moving
// the transform, like Camera3D — Point lights without a Transform3D sit at
// the origin); for Directional lights only `direction` matters and the
// transform is ignored. fields:
//   direction: unit-ish direction the light TRAVELS (Directional only;
//              normalized before upload — {0,-1,0} shines straight down)
//   color:     light color (255-based, normalized on upload)
//   intensity: brightness multiplier (0 = off)
//   radius:    Point only: distance at which the light fully attenuates
//
// only the first MAX_LIGHTS registered Light3D components act (first-
// registered wins, like the camera); the rest are ignored. a Light3D on an
// entity is implicitly enabled — no on/off flag. zero-value footgun: a bare
// Light3D{} has intensity 0 and a black color, so use light3d() below to
// build defaults in
Light3D :: struct {
	kind:      Light3DKind,
	direction: rl.Vector3,
	color:     rl.Color,
	intensity: f32,
	radius:    f32,
}

// cached snapshot of a light slot's last-uploaded values, used to skip
// redundant SetShaderValue calls when nothing changed (lights are static
// in grimm-3d, so this turns ~29 GL calls/frame into ~0 after frame 1)
LightCache :: struct {
	kind:      Light3DKind,
	position:  rl.Vector3,
	direction: rl.Vector3,
	color:     rl.Color,
	intensity: f32,
	radius:    f32,
	enabled:   bool,
}

// build a light with the common defaults already in place — a downward
// white directional at full intensity (a "sun"), radius 12 for points —
// so call sites only pass what they want to change:
//
//	sun := ecs.light3d()                                             // default sun
//	torch := ecs.light3d(.Point, color = rl.ORANGE, radius = 6)      // warm point
//	torch.intensity = 1.1
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

// the ambient term every lit model picks up before any light contribution:
// slightly cool so unlit sides stay readable instead of washing to black.
// exported — tweak it directly or through set_ambient
ambient: rl.Vector4 = {0.18, 0.18, 0.22, 1}

// recolor the ambient term. takes effect on the next draw frame; every
// lit model re-reads the uniform every frame, so mid-game changes are safe
set_ambient :: proc(a: rl.Vector4) {
	ambient = a
}

// the lighting shader, compiled lazily on the first frame update_lighting
// runs with a live GL context (plugins register before "startup" opens the
// window, so nothing shader-related may happen at registration time)
@(private)
light_shader: rl.Shader

// true once light_shader is compiled and the uniform locations below are
// cached. guards both the lazy init and the destroy-time unload
@(private)
shader_ready: bool

// one uniform-location cache slot per shader light. GetShaderLocation
// returns -1 for a name the shader doesn't have; a slot with -1 is skipped
// on upload rather than handed to SetShaderValue (which raylib would
// no-op, but guarding is cheaper than trusting it)
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

// dirty-tracking state for per-frame uniform uploads
@(private)
light_cache: [MAX_LIGHTS]LightCache

@(private)
light_cache_valid: [MAX_LIGHTS]bool

@(private)
ambient_cache: rl.Vector4

@(private)
ambient_cache_valid: bool
// vertex pass for the lighting shader: hand the fragment stage the model-
// space fragment position and normal. raylib auto-uploads matModel,
// matNormal and mvp for custom shaders whose uniforms carry these names —
// no manual matrix plumbing needed
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

// per-fragment Lambert lighting: ambient plus up to MAX_LIGHTS directional
// (constant direction, no attenuation) or point (inverse travel direction
// from the light position, quadratic falloff to zero at `radius`) lights.
// no shadows, no specular. colDiffuse is raylib's material diffuse color,
// which DrawModel overwrites with the model's tint per draw
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
    int   type;       // 0 = directional, 1 = point
    vec3  position;
    vec3  direction;  // directional travel direction (already normalized CPU-side)
    vec4  color;
    float intensity;
    float radius;
};
uniform Light lights[MAX_LIGHTS];
uniform vec4 colDiffuse;   // raylib uploads material color * DrawModel tint here
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

// compile the lighting shader and cache every uniform location. called
// once, on the first frame update_lighting runs with a ready window —
// plugin registration happens before startup opens it, so this must not
// run earlier. shader sources are cloned to cstrings with the temp
// allocator, the same rule as every raylib API that takes a C string
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

// free the lighting shader. registered in its own "lighting_unload" destroy
// set, ahead of the default set that holds CloseWindow — UnloadShader needs
// the GL context alive, same anchoring as the "models" set
@(private)
unload_lighting :: proc() {
	if shader_ready {
		rl.UnloadShader(light_shader)
		shader_ready = false
		// stale locations are meaningless once the shader is gone; mark every
		// slot un-uploaded so a re-init starts clean
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

// compare two cached light snapshots for equality (all fields)
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

// mark every cache slot dirty so the next update_lighting uploads all
@(private)
reset_light_cache :: proc() {
	for i in 0 ..< MAX_LIGHTS {
		light_cache_valid[i] = false
	}
	ambient_cache_valid = false
}

// push the world's lights into the shader and stamp every Model's material
// with it, every frame. the assignment is per-frame on purpose: models
// spawn dynamically (netgame remote cubes, gen_* calls during play), so a
// one-time stamp would miss anything spawned after the shader compiled.
// runs inside the 3d camera wrap, before draw_model, so the models it
// stamps draw with the shader in the same frame
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

	// default light: a world with no Light3D at all spawns a soft top-down
	// sun so existing scenes render shaded instead of unlit white — same
	// "first camera acts" philosophy. spawned BEFORE the slices below are
	// taken, because add_component can reallocate the Light3D storage and
	// a slice taken first would dangle
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

	// hand every model the lighting shader. materials is a ^Material array
	// behind the model handle, so writing the slice entry writes the model
	for &m in slice(world, Model) {
		if m.model.materials[0].shader.id != light_shader.id {
			m.model.materials[0].shader = light_shader
		}
	}

	// upload the first MAX_LIGHTS lights (first-registered wins) and
	// disable every remaining slot — but only when a slot's values (or
	// ambient) actually changed since the last upload
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

	// ambient re-reads every frame, so set_ambient lands immediately
	if !ambient_cache_valid || ambient != ambient_cache {
		if ambient_loc >= 0 {
			rl.SetShaderValue(light_shader, ambient_loc, &ambient, rl.ShaderUniformDataType.VEC4)
		}
		ambient_cache = ambient
		ambient_cache_valid = true
	}
}

// fill one shader light slot from one Light3D component. position comes
// from the owning entity's Transform3D (Point lights want one — document
// it on Light3D); a missing transform reads as the origin, which is still
// correct for Directional lights since they ignore position entirely
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
	// rl.Vector4 is [4]f32 in this vendor: r/g/b/a positional, 255-based
	// component values normalized on upload
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

// wire per-fragment 3d lighting into the app. its "lighting" prep set runs
// inside the 3d camera wrap, ahead of the "default" draw set, so the shader
// is stamped onto every model before draw_model runs in the same frame.
// add it AFTER DefaultPlugin:
//
//	ecs.add_plugin(&app, ecs.DefaultPlugin)
//	ecs.add_plugin(&app, ecs.Light3DPlugin)
//
// it is already included in Default3DPlugin. models keep drawing unlit
// without this plugin — lighting is opt-in per plugin, not global. the
// shader compiles lazily on the first draw frame (plugin registration runs
// before the window opens, so no GL calls may happen at registration time)
Light3DPlugin :: proc(app: ^App) {
	// "lighting" prep runs inside the 3D camera wrap, before draw_model
	init_system_set(app, "draw", "lighting", before("default"))
	add_system(app, "lighting", update_lighting)
	// unload with a live GL context, same anchoring as the "models" set
	init_system_set(app, "destroy", "lighting_unload", before("default"))
	add_system(app, "lighting_unload", unload_lighting)
}
