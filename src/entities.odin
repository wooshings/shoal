package shoal

import "core:fmt"

// an entity is just an id — a u32 handed out by spawn_entity and recorded in
// the app's entity list. no components hang off it, they live in storages
Entity :: distinct u32

// all the components of one type, kept together: dense holds them in add
// order, entities[i] is who owns dense[i], and sparse maps entity -> index
// into dense so get_component is a lookup instead of a scan.
// storages are usually declared as a global: `MyComp: Storage(MyCompType)`
Storage :: struct($T: typeid) {
	dense:    [dynamic]T,
	entities: [dynamic]Entity,
	sparse:   map[Entity]int,
}

// hand out a fresh entity id (the next index in app's entity list) and
// remember it. ids are never reused
spawn_entity :: proc(app: ^App) -> Entity {
	entity_num := len(&app.entities)
	entity: Entity = Entity(entity_num)
	append(&app.entities, entity)
	return entity
}

// add a component to an entity's storage — zero-initialized when you pass
// just the storage: add_component(entity, &Store), or filled in when you pass
// data too: add_component(entity, &Store, StoreComponent{...})
add_component :: proc {
	add_fresh_component,
	add_component_with_data,
}

// append a zeroed T to the storage and note where it landed in the sparse map
add_fresh_component :: proc(entity: Entity, storage: ^Storage($T)) {
	append(&storage.dense, T{})
	append(&storage.entities, entity)
	i := len(storage.dense) - 1
	defer storage.sparse[entity] = i
}

// same, but starts from a copy of the component you pass in
add_component_with_data :: proc(entity: Entity, storage: ^Storage($T), component: T) {
	append(&storage.dense, component)
	append(&storage.entities, entity)
	i := len(storage.dense) - 1
	defer storage.sparse[entity] = i
}

// the storage's dense array — the live backing array, not a copy of the data,
// so index i lines up with slice_entity()[i]. a later add_component that grows
// past capacity reallocates it, so don't hold the result across adds
slice :: proc(storage: ^Storage($T)) -> [dynamic]T {
	return storage.dense
}

// the entity ids backing the dense array, index-aligned with slice().
// same invalidation caveat: adds can reallocate it
slice_entity :: proc(storage: ^Storage($T)) -> [dynamic]Entity {
	return storage.entities
}

// ^T of the storage's first entry plus the entity that owns it — handy for
// singletons like Window. panics if the storage is empty
single :: proc(storage: ^Storage($T)) -> (^T, Entity) {
	return &storage.dense[0], storage.entities[0]
}

// a pointer to that entity's component, looked up through the sparse map.
// no existence check: an entity that was never added to this storage reads
// back as dense[0], and an empty storage panics
get_component :: proc(entity: Entity, storage: ^Storage($T)) -> ^T {
	return &storage.dense[storage.sparse[entity]]
}
