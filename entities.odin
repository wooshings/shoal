package shoal

Entity :: struct {
	id:         int,
	components: [dynamic]struct{},
}

spawn_entity :: proc(app: ^App) -> Entity {
	entity: Entity
	entity_len := len(&app.entities)
	entity.id = entity_len

	return entity
}

add_collection :: proc(app: ^App, component: $T) {

}
