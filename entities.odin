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

add_component :: proc(app: ^App, entity: Entity, storage: ^Storage($T)) {
	storage.data[entity] = T{}
}
