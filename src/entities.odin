package shoal

import "core:fmt"

Entity :: distinct u32

Storage :: struct($T: typeid) {
	dense:    [dynamic]T,
	entities: [dynamic]Entity,
	sparse:   map[Entity]int,
}

// adds a new entity id to app and returns it
spawn_entity :: proc(app: ^App) -> Entity {
	entity_num := len(&app.entities)
	entity: Entity = Entity(entity_num)
	append(&app.entities, entity)
	return entity
}

// create a new component of type and add to Storage
add_component :: proc {
	add_fresh_component,
	add_component_with_data,
}

// initializes new component of type and add to Storage
add_fresh_component :: proc(entity: Entity, storage: ^Storage($T)) {
	append(&storage.dense, T{})
	append(&storage.entities, entity)
	i := len(storage.dense) - 1
	defer storage.sparse[entity] = i
}

// creates a copy of component type with data and add to Storage
add_component_with_data :: proc(entity: Entity, storage: ^Storage($T), component: T) {
	append(&storage.dense, component)
	append(&storage.entities, entity)
	i := len(storage.dense) - 1
	defer storage.sparse[entity] = i
}

// get components saved in Storage
// returns storage.data
slice :: proc(storage: ^Storage($T)) -> [dynamic]T {
	return storage.dense
}

slice_entity :: proc(storage: ^Storage($T)) -> [dynamic]Entity {
	return storage.entities
}

// get component saved in Storage
// returns Entity and component of type
single :: proc(storage: ^Storage($T)) -> (^T, Entity) {
	return &storage.dense[0], storage.entities[0]
}

// get component of type from entity
get_component :: proc(entity: Entity, storage: ^Storage($T)) -> ^T {
	return &storage.dense[storage.sparse[entity]]
}
