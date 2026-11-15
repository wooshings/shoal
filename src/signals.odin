package shoal

Bus :: struct($T: typeid) {
	pending: [dynamic]T,
}

@(private)
Bus_Entry :: struct {
	bus:   rawptr,
	clear: proc(b: rawptr),
}

@(private)
buses: map[typeid]Bus_Entry

@(private)
get_bus :: proc($T: typeid) -> ^Bus(T) {
	if entry, exists := buses[T]; exists {
		return (^Bus(T))(entry.bus)
	}
	bus := new(Bus(T))
	buses[T] = {
		bus   = bus,
		clear = clear_bus(T),
	}
	return bus
}

@(private)
clear_bus :: proc($T: typeid) -> proc(b: rawptr) {
	return proc(b: rawptr) {
			bus := (^Bus(T))(b)
			clear(&bus.pending)
		}
}

write :: proc {
	write_empty,
	write_with_data,
}

write_empty :: proc($T: typeid) {
	bus := get_bus(T)
	append(&bus.pending, T{})
}

write_with_data :: proc(data: $T) {
	bus := get_bus(T)
	append(&bus.pending, data)
}

read :: proc($T: typeid) -> []T {
	bus := get_bus(T)
	if len(bus.pending) == 0 {return nil}
	result := make([]T, len(bus.pending), context.temp_allocator)
	copy(result, bus.pending[:])
	return result
}

signal_system :: proc() {
	for type_id, e in buses {
		if type_id == typeid_of(ExitApp) { continue }
		e.clear(e.bus)
	}
}
