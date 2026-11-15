package shoal

import "core:fmt"
import "core:mem"

Entity :: distinct u32

World :: struct {
	entities:     [dynamic]Entity,
	storage_count: u32,
	storages:     [dynamic]rawptr,
	type_indices: map[typeid]u32,
}

Storage_Entry :: struct {
	storage: rawptr,
	drop:    proc(storage: rawptr),
}

Storage :: struct($T: typeid) {
	dense:    [dynamic]T,
	entities: [dynamic]Entity,
	sparse:   [dynamic]int,
}

@(private)
get_storage :: proc(world: ^World, $T: typeid) -> ^Storage(T) {
	if idx, exists := world.type_indices[T]; exists {
		return (^Storage(T))(world.storages[idx])
	}

	idx := world.storage_count
	world.type_indices[T] = idx
	world.storage_count += 1

	storage := new(Storage(T))

	for int(len(world.storages)) <= int(idx) {
		append(&world.storages, nil)
	}
	world.storages[idx] = storage
	return storage
}

@(private)
drop_storage :: proc($T: typeid) -> proc(storage: rawptr) {
	return proc(storage: rawptr) {
			s := (^Storage(T))(storage)
			s.dense = nil
			s.entities = nil
			s.sparse = nil

		}
}

destroy_world :: proc(world: ^World) {

	_ = world
}

spawn_entity :: proc(world: ^World) -> Entity {
	entity_num := len(world.entities)
	entity: Entity = Entity(entity_num)
	append(&world.entities, entity)
	return entity
}

add_component :: proc {
	add_fresh_component,
	add_component_with_data,
}

@(private)
add_fresh_component :: proc(world: ^World, entity: Entity, $T: typeid) {
	storage := get_storage(world, T)
	i := len(storage.dense)
	append(&storage.dense, T{})
	append(&storage.entities, entity)
	grow_sparse(T, storage, entity)
	storage.sparse[entity] = i
}

@(private)
add_component_with_data :: proc(world: ^World, entity: Entity, component: $T) {
	storage := get_storage(world, T)
	i := len(storage.dense)
	append(&storage.dense, component)
	append(&storage.entities, entity)
	grow_sparse(T, storage, entity)
	storage.sparse[entity] = i
}

@(private)
grow_sparse :: proc($T: typeid, storage: ^Storage(T), entity: Entity) {
	if entity < Entity(u32(len(storage.sparse))) {
		return
	}
	old_len := len(storage.sparse)
	resize(&storage.sparse, int(entity) + 1)
	for j := old_len; j <= int(entity); j += 1 {
		storage.sparse[j] = -1
	}
}

slice :: proc(world: ^World, $T: typeid) -> [dynamic]T {
	return get_storage(world, T).dense
}

slice_entity :: proc(world: ^World, $T: typeid) -> [dynamic]Entity {
	return get_storage(world, T).entities
}

single :: proc(world: ^World, $T: typeid) -> (^T, Entity) {
	storage := get_storage(world, T)
	if len(storage.dense) == 0 {
		panic(fmt.tprintf("single: no entity has component {}", typeid_of(T)))
	}
	return &storage.dense[0], storage.entities[0]
}

get_component :: proc(world: ^World, entity: Entity, $T: typeid) -> ^T {
	storage := get_storage(world, T)
	if u32(entity) >= u32(len(storage.sparse)) || storage.sparse[u32(entity)] == -1 {
		panic(fmt.tprintf("get_component: entity {} has no component {}", entity, typeid_of(T)))
	}
	return &storage.dense[storage.sparse[u32(entity)]]
}

has_component :: proc(world: ^World, entity: Entity, $T: typeid) -> bool {
	storage := get_storage(world, T)
	if u32(entity) >= u32(len(storage.sparse)) {
		return false
	}
	return storage.sparse[u32(entity)] != -1
}

try_get_component :: proc(world: ^World, entity: Entity, $T: typeid) -> (component: ^T, ok: bool) {
	storage := get_storage(world, T)
	e := u32(entity)
	if e >= u32(len(storage.sparse)) || storage.sparse[e] == -1 {
		return nil, false
	}
	return &storage.dense[storage.sparse[e]], true
}
