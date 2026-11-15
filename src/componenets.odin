package shoal

import rl "vendor:raylib"

Window :: struct {
	width:      i32,
	height:     i32,
	title:      string,
	background: rl.Color,
}

Cursor :: struct {
	position: rl.Vector2,
}

Sprite :: struct {
	texture:  rl.Texture2D,
	source:   rl.Rectangle,
	scale:    rl.Vector2,
	tint:     rl.Color,
	flip_h:   bool,
	flip_v:   bool,
}

sprite :: proc(
	texture: rl.Texture2D,
	scale := rl.Vector2{1, 1},
	tint := rl.WHITE,
	source := rl.Rectangle{},
) -> Sprite {
	return Sprite{texture = texture, scale = scale, tint = tint, source = source}
}

Transform :: struct {
	translation: rl.Vector2,
	rotation:    f32,
}

Camera :: struct {
	zoom: f32,
}

Transform3D :: struct {
	translation: rl.Vector3,
	rotation:    rl.Vector3,
	scale:       rl.Vector3,
}

transform3d :: proc(
	translation := rl.Vector3{},
	rotation := rl.Vector3{},
	scale := rl.Vector3{1, 1, 1},
) -> Transform3D {
	return Transform3D{translation = translation, rotation = rotation, scale = scale}
}

Camera3D :: struct {
	target:     rl.Vector3,
	up:         rl.Vector3,
	fovy:       f32,
	projection: rl.CameraProjection,
}

camera3d :: proc(
	target := rl.Vector3{},
	up := rl.Vector3{0, 1, 0},
	fovy: f32 = 45,
	projection := rl.CameraProjection.PERSPECTIVE,
) -> Camera3D {
	return Camera3D{target = target, up = up, fovy = fovy, projection = projection}
}

Model :: struct {
	model: rl.Model,
	tint:  rl.Color,
}

model :: proc(m: rl.Model, tint := rl.WHITE) -> Model {
	return Model{model = m, tint = tint}
}

Collider2D :: struct {
	solid:   bool,
	offset:  rl.Vector2,
	width:   f32,
	height:  f32,
	size:    rl.Vector2,
	radius:  f32,
	layer:   u32,
	mask:    u32,
}

Collider :: Collider2D
Collider2d :: Collider2D
Collision :: Collider2D
Collision2D :: Collider2D
Solid :: Collider2D
Solid2D :: Collider2D
BoxCollider2D :: Collider2D
SphereCollider2D :: Collider2D
AABB2D :: Collider2D
BoundingCircle :: Collider2D

collider2d :: proc(
	width: f32 = 1,
	height: f32 = 1,
	solid: bool = true,
	offset := rl.Vector2{},
	radius: f32 = 0,
) -> Collider2D {
	return Collider2D{
		solid  = solid,
		offset = offset,
		width  = width,
		height = height,
		size   = {width, height},
		radius = radius,
	}
}

Collider3D :: struct {
	solid:   bool,
	offset:  rl.Vector3,
	width:   f32,
	height:  f32,
	length:  f32,
	size:    rl.Vector3,
	radius:  f32,
	layer:   u32,
	mask:    u32,
}

Collider3d :: Collider3D
Collision3D :: Collider3D
Solid3D :: Collider3D
BoxCollider :: Collider3D
BoxCollider3D :: Collider3D
SphereCollider :: Collider3D
SphereCollider3D :: Collider3D
AABB :: Collider3D
AABB3D :: Collider3D
BoundingBox :: Collider3D

collider3d :: proc(
	width: f32 = 1,
	height: f32 = 1,
	length: f32 = 1,
	solid: bool = true,
	offset := rl.Vector3{},
	radius: f32 = 0,
) -> Collider3D {
	return Collider3D{
		solid  = solid,
		offset = offset,
		width  = width,
		height = height,
		length = length,
		size   = {width, height, length},
		radius = radius,
	}
}

RayCollider2D :: struct {
	solid:     bool,
	origin:    rl.Vector2,
	direction: rl.Vector2,
	length:    f32,
	offset:    rl.Vector2,
	layer:     u32,
	mask:      u32,
}

RayCollider2d :: RayCollider2D
RaycastCollider2D :: RayCollider2D
Ray2D :: RayCollider2D
Ray2d :: RayCollider2D

raycollider2d :: proc(
	direction := rl.Vector2{1, 0},
	length: f32 = 100,
	solid: bool = false,
	offset := rl.Vector2{},
) -> RayCollider2D {
	return RayCollider2D{solid = solid, direction = direction, length = length, offset = offset}
}

RayCollider3D :: struct {
	solid:     bool,
	origin:    rl.Vector3,
	direction: rl.Vector3,
	length:    f32,
	offset:    rl.Vector3,
	layer:     u32,
	mask:      u32,
}

RayCollider3d :: RayCollider3D
RaycastCollider3D :: RayCollider3D
Ray3D :: RayCollider3D
Ray3d :: RayCollider3D
Ray :: RayCollider3D

raycollider3d :: proc(
	direction := rl.Vector3{0, 0, 1},
	length: f32 = 100,
	solid: bool = false,
	offset := rl.Vector3{},
) -> RayCollider3D {
	return RayCollider3D{solid = solid, direction = direction, length = length, offset = offset}
}
