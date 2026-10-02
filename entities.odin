package shoal

Entity :: distinct u32

Storage :: struct($T: typeid) {
	data: map[Entity]T,
}

spawn_entity :: proc(app: ^App, $T: typeid) -> Entity {
	entity: Entity
	return entity
}

add_collection :: proc(app: ^App, $T: typeid) {
	storage: ^Storage(T)
	app.storages[T] = storage
}

query :: proc(app: ^App, $T: typeid) {

}
