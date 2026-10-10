package shoal

import "core:fmt"

Entity :: distinct u32

Storage :: struct($T: typeid) {
	data: map[Entity]T,
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
	storage.data[entity] = T{}
}

// creates a copy of component type with data and add to Storage
add_component_with_data :: proc(entity: Entity, storage: ^Storage($T), component: T) {
	storage.data[entity] = component
}

// get components saved in Storage
// returns storage.data
slice :: proc(storage: ^Storage($T)) -> map[Entity]T {
	return storage.data
}

// get component saved in Storage
// returns Entity and component of type
single :: proc(storage: ^Storage($T)) -> (Entity, ^T) {
	for i, &v in slice(storage) {
		return i, &v
	}
	return 0, nil
}

// get component of type from entity
get_component :: proc(entity: Entity, storage: ^Storage($T)) -> ^T {
	if _, exists := storage.data[entity]; exists {
		return &storage.data[entity]
	}
	return new(T)
}
