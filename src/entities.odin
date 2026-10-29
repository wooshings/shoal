package shoal

import "core:fmt"
import "core:mem"

// an entity is an id, a u32 handed out by spawn_entity and recorded in
// the world's entity list. no components hang off it, they live in storages
Entity :: distinct u32

// all the game data: every entity id handed out by spawn_entity, plus one
// storage per component type, created lazily the first time anything touches
// that component. a zero World{} is ready to use: the entity list grows on
// append and the storage map makes itself on first component add. App holds
// one of these; systems are handed a ^World directly, and plugins reach it
// through their ^App via get_world. never copy a World by value: the copy
// duplicates the header but shares the heap storages, so destroying both
// copies double-frees. pass ^World around, don't copy
World :: struct {
	entities: [dynamic]Entity,
	storages: map[typeid]Storage_Entry,
}

// one entry in the world's storage map: the storage itself, type-erased so
// every component fits the same map, plus a proc that knows how to destroy
// it. storages are heap-allocated once per world so the map can rehash
// without moving them around
Storage_Entry :: struct {
	storage: rawptr,
	drop:    proc(storage: rawptr),
}

// all the components of one type, kept together: dense holds them in add
// order, entities[i] is who owns dense[i], and sparse maps entity -> index
// into dense so get_component is a lookup instead of a scan.
// you never declare one of these yourself; the world creates storages
// on first access, see get_storage below
Storage :: struct($T: typeid) {
	dense:    [dynamic]T,
	entities: [dynamic]Entity,
	sparse:   map[Entity]int,
}

// the storage for component type T inside this world, created on first
// access, the same lazy pattern as the signal buses in signals.odin. every
// world has its own copy, so two worlds never share components. package-
// private on purpose: outside code goes through add_component/slice/single/
// get_component, which find storages for you
@(private)
get_storage :: proc(world: ^World, $T: typeid) -> ^Storage(T) {
	if world.storages == nil {
		world.storages = {}
	}
	if entry, exists := world.storages[T]; exists {
		return (^Storage(T))(entry.storage)
	}
	storage := new(Storage(T))
	world.storages[T] = {
		storage = storage,
		drop    = drop_storage(T),
	}
	return storage
}

// called once per component type, hands destroy_world a rawptr drop for
// that storage
@(private)
drop_storage :: proc($T: typeid) -> proc(storage: rawptr) {
	return proc(storage: rawptr) {
			s := (^Storage(T))(storage)
			delete(s.dense)
			delete(s.entities)
			delete(s.sparse)
			mem.free(s)
		}
}

// free everything the world owns: every storage's data and the storages
// themselves, the storage map, and the entity list. the world is left empty
// and safe to drop. this is teardown, not per-frame cleanup; nothing needs
// calling while the app runs
destroy_world :: proc(world: ^World) {
	for _, entry in world.storages {
		entry.drop(entry.storage)
	}
	delete(world.storages)
	delete(world.entities)
	world.storages = nil
	world.entities = nil
}

// hand out a fresh entity id (the next index in the world's entity list) and
// remember it. ids are never reused
spawn_entity :: proc(world: ^World) -> Entity {
	entity_num := len(world.entities)
	entity: Entity = Entity(entity_num)
	append(&world.entities, entity)
	return entity
}

// add a component to an entity, zero-initialized when you pass just the
// type: add_component(world, entity, MyComponent), or filled in when you
// pass data too: add_component(world, entity, MyComponent{...}). the world's
// storage for that type is created on the spot if this is the first one
add_component :: proc {
	add_fresh_component,
	add_component_with_data,
}

// append a zeroed T to the entity's storage and note where it landed in the
// sparse map
add_fresh_component :: proc(world: ^World, entity: Entity, $T: typeid) {
	storage := get_storage(world, T)
	append(&storage.dense, T{})
	append(&storage.entities, entity)
	i := len(storage.dense) - 1
	storage.sparse[entity] = i
}

// same, but starts from a copy of the component you pass in
add_component_with_data :: proc(world: ^World, entity: Entity, component: $T) {
	storage := get_storage(world, T)
	append(&storage.dense, component)
	append(&storage.entities, entity)
	i := len(storage.dense) - 1
	storage.sparse[entity] = i
}

// every component of type T in the world: the live backing array, not a
// copy of the data, so index i lines up with slice_entity()[i]. a later
// add_component that grows past capacity reallocates it, so don't hold the
// result across adds
slice :: proc(world: ^World, $T: typeid) -> [dynamic]T {
	return get_storage(world, T).dense
}

// the entity ids backing the dense array, index-aligned with slice().
// same invalidation caveat: adds can reallocate it
slice_entity :: proc(world: ^World, $T: typeid) -> [dynamic]Entity {
	return get_storage(world, T).entities
}

// ^T of the world's first entry of that component plus the entity that owns
// it, handy for singletons like WindowComponent. panics with a readable
// message if no entity has the component yet
single :: proc(world: ^World, $T: typeid) -> (^T, Entity) {
	storage := get_storage(world, T)
	if len(storage.dense) == 0 {
		panic(fmt.tprintf("single: no entity has component {}", typeid_of(T)))
	}
	return &storage.dense[0], storage.entities[0]
}

// a pointer to that entity's component, looked up through the sparse map.
// panics with a readable message if this specific entity was never added to
// the storage. use has_component or try_get_component when you aren't sure
get_component :: proc(world: ^World, entity: Entity, $T: typeid) -> ^T {
	storage := get_storage(world, T)
	if i, ok := storage.sparse[entity]; ok {
		return &storage.dense[i]
	}
	panic(fmt.tprintf("get_component: entity {} has no component {}", entity, typeid_of(T)))
}

// true iff this specific entity has the component. probing a component the
// entity lacks (or a type nothing has added yet) is safe: it never panics
// and never reports a different entity's entry. fine to call every frame,
// though the first probe of a never-seen type lazily creates its storage
has_component :: proc(world: ^World, entity: Entity, $T: typeid) -> bool {
	storage := get_storage(world, T)
	_, ok := storage.sparse[entity]
	return ok
}

// the entity's component and a flag saying whether it's there: (nil, false)
// when this entity never got the component, no panic. the pointer-flavored
// alternative to has_component + get_component for plugins and systems that
// probe components they don't own
try_get_component :: proc(world: ^World, entity: Entity, $T: typeid) -> (component: ^T, ok: bool) {
	storage := get_storage(world, T)
	if i, exists := storage.sparse[entity]; exists {
		return &storage.dense[i], true
	}
	return nil, false
}
