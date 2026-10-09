package shoal

import "core:fmt"

Entity :: distinct u32

Storage :: struct($T: typeid) {
	data: map[Entity]T,
}

spawn_entity :: proc(app: ^App) -> Entity {
	entity_num := len(&app.entities)
	entity: Entity = Entity(entity_num)
	append(&app.entities, entity)
	return entity
}

add_component :: proc {
	add_fresh_component,
	add_component_with_data,
}

add_fresh_component :: proc(entity: Entity, storage: ^Storage($T)) {
	storage.data[entity] = T{}
}

add_component_with_data :: proc(entity: Entity, storage: ^Storage($T), component: T) {
	storage.data[entity] = component
}

slice :: proc(storage: ^Storage($T)) -> map[Entity]T {
	return storage.data
}

single :: proc(storage: ^Storage($T)) -> (Entity, ^T) {
	for i, &v in slice(storage) {
		return i, &v
	}
	return Entity{}, new(T)
}

get_component :: proc(entity: Entity, storage: ^Storage($T)) -> ^T {
	if c, exists := &storage.data[entity]; exists {
		return c
	}
	return new(T)
}
