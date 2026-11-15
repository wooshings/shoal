package shoal

import "core:math"
import rl "vendor:raylib"

collision_filter :: proc(layer_a, mask_a, layer_b, mask_b: u32) -> bool {
	ma := mask_a
	if ma == 0 { ma = 0xFFFFFFFF }
	mb := mask_b
	if mb == 0 { mb = 0xFFFFFFFF }
	return (ma & (1 << layer_b)) != 0 && (mb & (1 << layer_a)) != 0
}

CollisionEvent2D :: struct {
	a: Entity,
	b: Entity,
}
Collision2DEvent :: CollisionEvent2D
Collided2D :: CollisionEvent2D
CollisionStarted2D :: CollisionEvent2D

CollisionEvent3D :: struct {
	a: Entity,
	b: Entity,
}
Collision3DEvent :: CollisionEvent3D
Collided3D :: CollisionEvent3D
CollisionStarted3D :: CollisionEvent3D

RaycastHit2D :: struct {
	ray:      Entity,
	target:   Entity,
	point:    rl.Vector2,
	distance: f32,
}
RaycastHitEvent2D :: RaycastHit2D

RaycastHit3D :: struct {
	ray:      Entity,
	target:   Entity,
	point:    rl.Vector3,
	normal:   rl.Vector3,
	distance: f32,
}
RaycastHitEvent3D :: RaycastHit3D

collider2d_center :: proc(t: ^Transform, c: ^Collider2D) -> rl.Vector2 {
	return t.translation + c.offset
}

collider2d_size :: proc(c: ^Collider2D) -> rl.Vector2 {
	if c.size.x > 0 || c.size.y > 0 { return c.size }
	return rl.Vector2{c.width, c.height}
}

overlap2d :: proc(ta: ^Transform, ca: ^Collider2D, tb: ^Transform, cb: ^Collider2D) -> bool {
	if !collision_filter(ca.layer, ca.mask, cb.layer, cb.mask) { return false }
	ca_sz := collider2d_size(ca)
	cb_sz := collider2d_size(cb)
	center_a := collider2d_center(ta, ca)
	center_b := collider2d_center(tb, cb)

	if ca.radius > 0 && cb.radius > 0 {
		d := rl.Vector2Distance(center_a, center_b)
		return d <= ca.radius + cb.radius
	}

	if ca.radius > 0 {

		half := cb_sz * 0.5
		closest := rl.Vector2{
			clamp(center_a.x, center_b.x - half.x, center_b.x + half.x),
			clamp(center_a.y, center_b.y - half.y, center_b.y + half.y),
		}
		d := rl.Vector2Distance(center_a, closest)
		return d <= ca.radius
	}
	if cb.radius > 0 {
		half := ca_sz * 0.5
		closest := rl.Vector2{
			clamp(center_b.x, center_a.x - half.x, center_a.x + half.x),
			clamp(center_b.y, center_a.y - half.y, center_a.y + half.y),
		}
		d := rl.Vector2Distance(center_b, closest)
		return d <= cb.radius
	}

	half_a := ca_sz * 0.5
	half_b := cb_sz * 0.5
	return math.abs(center_a.x - center_b.x) <= half_a.x + half_b.x &&
		math.abs(center_a.y - center_b.y) <= half_a.y + half_b.y
}

collider3d_size :: proc(c: ^Collider3D) -> rl.Vector3 {
	if c.size.x > 0 || c.size.y > 0 || c.size.z > 0 { return c.size }
	return rl.Vector3{c.width, c.height, c.length}
}

overlap3d :: proc(ta: ^Transform3D, ca: ^Collider3D, tb: ^Transform3D, cb: ^Collider3D) -> bool {
	if !collision_filter(ca.layer, ca.mask, cb.layer, cb.mask) { return false }
	sa := collider3d_size(ca)
	sb := collider3d_size(cb)
	center_a := ta.translation + ca.offset
	center_b := tb.translation + cb.offset

	if ca.radius > 0 && cb.radius > 0 {
		d := rl.Vector3Distance(center_a, center_b)
		return d <= ca.radius + cb.radius
	}

	if ca.radius > 0 {
		half := sb * 0.5
		closest := rl.Vector3{
			clamp(center_a.x, center_b.x - half.x, center_b.x + half.x),
			clamp(center_a.y, center_b.y - half.y, center_b.y + half.y),
			clamp(center_a.z, center_b.z - half.z, center_b.z + half.z),
		}
		d := rl.Vector3Distance(center_a, closest)
		return d <= ca.radius
	}
	if cb.radius > 0 {
		half := sa * 0.5
		closest := rl.Vector3{
			clamp(center_b.x, center_a.x - half.x, center_a.x + half.x),
			clamp(center_b.y, center_a.y - half.y, center_a.y + half.y),
			clamp(center_b.z, center_a.z - half.z, center_a.z + half.z),
		}
		d := rl.Vector3Distance(center_b, closest)
		return d <= cb.radius
	}

	half_a := sa * 0.5
	half_b := sb * 0.5
	return math.abs(center_a.x - center_b.x) <= half_a.x + half_b.x &&
		math.abs(center_a.y - center_b.y) <= half_a.y + half_b.y &&
		math.abs(center_a.z - center_b.z) <= half_a.z + half_b.z
}

collision_system :: proc(world: ^World) {

	{
		comps := slice(world, Collider2D)
		ents := slice_entity(world, Collider2D)
		n := len(comps)
		for i in 0 ..< n {
			ei := ents[i]
			if !has_component(world, ei, Transform) { continue }
			ti := get_component(world, ei, Transform)
			for j in i + 1 ..< n {
				ej := ents[j]
				if !has_component(world, ej, Transform) { continue }
				tj := get_component(world, ej, Transform)
				if overlap2d(ti, &comps[i], tj, &comps[j]) {
					write(CollisionEvent2D{a = ei, b = ej})
				}
			}
		}
	}

	{
		comps := slice(world, Collider3D)
		ents := slice_entity(world, Collider3D)
		n := len(comps)
		for i in 0 ..< n {
			ei := ents[i]
			if !has_component(world, ei, Transform3D) { continue }
			ti := get_component(world, ei, Transform3D)
			for j in i + 1 ..< n {
				ej := ents[j]
				if !has_component(world, ej, Transform3D) { continue }
				tj := get_component(world, ej, Transform3D)
				if overlap3d(ti, &comps[i], tj, &comps[j]) {
					write(CollisionEvent3D{a = ei, b = ej})
				}
			}
		}
	}

	{
		rays := slice(world, RayCollider3D)
		ray_ents := slice_entity(world, RayCollider3D)
		colliders := slice(world, Collider3D)
		coll_ent := slice_entity(world, Collider3D)
		for ri in 0 ..< len(rays) {
			re := ray_ents[ri]
			transform: ^Transform3D
			if has_component(world, re, Transform3D) {
				transform = get_component(world, re, Transform3D)
			}
			origin := rays[ri].origin
			if transform != nil { origin = origin + transform.translation + rays[ri].offset }
			dir := rays[ri].direction
			if rl.Vector3Length(dir) == 0 { dir = rl.Vector3{0, 0, 1} }
			dir = rl.Vector3Normalize(dir)
			length := rays[ri].length
			if length <= 0 { length = 100 }
			for ci in 0 ..< len(colliders) {
				ce := coll_ent[ci]
				if ce == re { continue }
				if !has_component(world, ce, Transform3D) { continue }
				ct := get_component(world, ce, Transform3D)
				if !collision_filter(rays[ri].layer, rays[ri].mask, colliders[ci].layer, colliders[ci].mask) { continue }

				ray := rl.Ray{position = origin, direction = dir}
				size := collider3d_size(&colliders[ci])
				half := size * 0.5
				center := ct.translation + colliders[ci].offset
				hit: bool
				dist: f32
				if colliders[ci].radius > 0 {
					rc := rl.GetRayCollisionSphere(ray, center, colliders[ci].radius)
					hit = rc.hit
					dist = rc.distance
				} else {
					box := rl.BoundingBox{min = center - half, max = center + half}
					rc := rl.GetRayCollisionBox(ray, box)
					hit = rc.hit
					dist = rc.distance
				}
				if hit && dist >= 0 && dist <= length {
					write(RaycastHit3D{ray = re, target = ce, point = ray.position + dir*dist, normal = rl.Vector3{}, distance = dist})
				}
			}
		}
	}

	{
		rays := slice(world, RayCollider2D)
		ray_ents := slice_entity(world, RayCollider2D)
		colliders := slice(world, Collider2D)
		coll_ent := slice_entity(world, Collider2D)
		for ri in 0 ..< len(rays) {
			re := ray_ents[ri]
			transform: ^Transform
			if has_component(world, re, Transform) {
				transform = get_component(world, re, Transform)
			}
			origin := rays[ri].origin
			if transform != nil { origin = origin + transform.translation + rays[ri].offset }
			dir := rays[ri].direction
			if rl.Vector2Length(dir) == 0 { dir = rl.Vector2{1, 0} }
			dir = rl.Vector2Normalize(dir)
			length := rays[ri].length
			if length <= 0 { length = 100 }
			for ci in 0 ..< len(colliders) {
				ce := coll_ent[ci]
				if ce == re { continue }
				if !has_component(world, ce, Transform) { continue }
				ct := get_component(world, ce, Transform)
				if !collision_filter(rays[ri].layer, rays[ri].mask, colliders[ci].layer, colliders[ci].mask) { continue }
				center := collider2d_center(ct, &colliders[ci])
				sz := collider2d_size(&colliders[ci])

				if colliders[ci].radius > 0 {

					oc := origin - center
					a := rl.Vector2DotProduct(dir, dir)
					b := 2 * rl.Vector2DotProduct(oc, dir)
					c := rl.Vector2DotProduct(oc, oc) - colliders[ci].radius*colliders[ci].radius
					disc := b*b - 4*a*c
					if disc >= 0 {
						t := (-b - math.sqrt(disc)) / (2*a)
						if t >= 0 && t <= length {
							write(RaycastHit2D{ray = re, target = ce, point = origin + dir*t, distance = t})
						}
					}
					continue
				}

				half := sz * 0.5
				minb := center - half
				maxb := center + half
				tmin: f32 = 0
				tmax: f32 = length

				if math.abs(dir.x) < 1e-8 {
					if origin.x < minb.x || origin.x > maxb.x { continue }
				} else {
					inv := 1.0 / dir.x
					t1 := (minb.x - origin.x) * inv
					t2 := (maxb.x - origin.x) * inv
					if t1 > t2 { t1, t2 = t2, t1 }
					if t1 > tmin { tmin = t1 }
					if t2 < tmax { tmax = t2 }
					if tmin > tmax { continue }
				}
				if math.abs(dir.y) < 1e-8 {
					if origin.y < minb.y || origin.y > maxb.y { continue }
				} else {
					inv := 1.0 / dir.y
					t1 := (minb.y - origin.y) * inv
					t2 := (maxb.y - origin.y) * inv
					if t1 > t2 { t1, t2 = t2, t1 }
					if t1 > tmin { tmin = t1 }
					if t2 < tmax { tmax = t2 }
					if tmin > tmax { continue }
				}
				if tmin >= 0 && tmin <= length {
					write(RaycastHit2D{ray = re, target = ce, point = origin + dir*tmin, distance = tmin})
				}
			}
		}
	}
}

raycast2d :: proc(world: ^World, origin, direction: rl.Vector2, max_distance: f32 = 1e9) -> (hit: bool, entity: Entity, point: rl.Vector2, distance: f32) {
	dir := direction
	if rl.Vector2Length(dir) == 0 { dir = rl.Vector2{1, 0} }
	dir = rl.Vector2Normalize(dir)
	best_dist := max_distance
	found := false

	comps := slice(world, Collider2D)
	ents := slice_entity(world, Collider2D)
	for i in 0 ..< len(comps) {
		e := ents[i]
		if !has_component(world, e, Transform) { continue }
		t := get_component(world, e, Transform)
		c := &comps[i]
		center := collider2d_center(t, c)
		sz := collider2d_size(c)

		if c.radius > 0 {
			oc := origin - center
			a := rl.Vector2DotProduct(dir, dir)
			b := 2 * rl.Vector2DotProduct(oc, dir)
			cc := rl.Vector2DotProduct(oc, oc) - c.radius*c.radius
			disc := b*b - 4*a*cc
			if disc >= 0 {
				tt := (-b - math.sqrt(disc)) / (2*a)
				if tt >= 0 && tt <= best_dist {
					best_dist = tt
					entity = e
					point = origin + dir*tt
					distance = tt
					found = true
				}
			}
			continue
		}

		half := sz * 0.5
		minb := center - half
		maxb := center + half
		tmin: f32 = 0
		tmax: f32 = best_dist
		ok := true
		if math.abs(dir.x) < 1e-8 {
			if origin.x < minb.x || origin.x > maxb.x { ok = false }
		} else {
			inv := 1.0 / dir.x
			t1 := (minb.x - origin.x) * inv
			t2 := (maxb.x - origin.x) * inv
			if t1 > t2 { t1, t2 = t2, t1 }
			if t1 > tmin { tmin = t1 }
			if t2 < tmax { tmax = t2 }
			if tmin > tmax { ok = false }
		}
		if ok {
			if math.abs(dir.y) < 1e-8 {
				if origin.y < minb.y || origin.y > maxb.y { ok = false }
			} else {
				inv := 1.0 / dir.y
				t1 := (minb.y - origin.y) * inv
				t2 := (maxb.y - origin.y) * inv
				if t1 > t2 { t1, t2 = t2, t1 }
				if t1 > tmin { tmin = t1 }
				if t2 < tmax { tmax = t2 }
				if tmin > tmax { ok = false }
			}
		}
		if ok && tmin >= 0 && tmin <= best_dist {
			best_dist = tmin
			entity = e
			point = origin + dir*tmin
			distance = tmin
			found = true
		}
	}
	hit = found
	return
}

raycast3d :: proc {
	raycast3d_ray,
	raycast3d_vec,
}

raycast3d_ray :: proc(world: ^World, ray: rl.Ray, max_distance: f32 = 1e9) -> (hit: bool, entity: Entity, point, normal: rl.Vector3, distance: f32) {
	dir := ray.direction
	if rl.Vector3Length(dir) == 0 { dir = rl.Vector3{0, 0, 1} }
	dir = rl.Vector3Normalize(dir)
	r := rl.Ray{position = ray.position, direction = dir}
	best_dist := max_distance
	found := false

	comps := slice(world, Collider3D)
	ents := slice_entity(world, Collider3D)
	for i in 0 ..< len(comps) {
		e := ents[i]
		if !has_component(world, e, Transform3D) { continue }
		t := get_component(world, e, Transform3D)
		c := &comps[i]
		center := t.translation + c.offset
		size := collider3d_size(c)
		rc: rl.RayCollision
		if c.radius > 0 {
			rc = rl.GetRayCollisionSphere(r, center, c.radius)
		} else {
			half := size * 0.5
			box := rl.BoundingBox{min = center - half, max = center + half}
			rc = rl.GetRayCollisionBox(r, box)
		}
		if rc.hit && rc.distance >= 0 && rc.distance <= best_dist {
			best_dist = rc.distance
			entity = e
			point = rc.point
			normal = rc.normal
			distance = rc.distance
			found = true
		}
	}
	hit = found
	return
}

raycast3d_vec :: proc(world: ^World, origin, direction: rl.Vector3, max_distance: f32 = 1e9) -> (hit: bool, entity: Entity, point, normal: rl.Vector3, distance: f32) {
	ray := rl.Ray{position = origin, direction = direction}
	return raycast3d_ray(world, ray, max_distance)
}

CollisionPlugin :: proc(app: ^App) {
	init_system_set(app, "update", "collision")
	add_system(app, "collision", collision_system)
}

CollisionPlugin2D :: CollisionPlugin
CollisionPlugin3D :: CollisionPlugin
PhysicsPlugin :: CollisionPlugin
RaycastPlugin :: CollisionPlugin

ray_cast_2d :: raycast2d
ray_cast_3d :: raycast3d
raycast_2d :: raycast2d
raycast_3d :: raycast3d
