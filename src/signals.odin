package shoal

// per-type signal bus, created on first use.
// one system writes a signal with data, any number of other systems read it
// after. same-frame reads only work until signal_system clears the buses at
// POST_UPDATE — see read/signal_system below for the details.
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

// called once per payload type, hands signal_system a rawptr clear for that bus
@(private)
clear_bus :: proc($T: typeid) -> proc(b: rawptr) {
	return proc(b: rawptr) {
			bus := (^Bus(T))(b)
			clear(&bus.pending)
		}
}

// queue a signal, readable until signal_system clears it at POST_UPDATE.
// note POST_UPDATE runs before PRE_DRAW/DRAW, so a reader sees exactly what's
// been written since the last POST_UPDATE: UPDATE systems see same-frame
// writes, but a DRAW system only sees writes made after this frame's
// POST_UPDATE (by PRE_DRAW or earlier DRAW systems)
// queue an empty payload by passing the bare type: write(MySignal)
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

// every signal of type T written since the last POST_UPDATE, non-consuming,
// empty if none. iterate it: for s in read(MySignal)
// copied into context.temp_allocator so write() during iteration can't
// reallocate the pending buffer out from under you — but that means the result
// dies with the frame's temp arena, don't hold onto it past that
read :: proc($T: typeid) -> []T {
	bus := get_bus(T)
	if len(bus.pending) == 0 {return nil}
	result := make([]T, len(bus.pending), context.temp_allocator)
	copy(result, bus.pending[:])
	return result
}

// runs at POST_UPDATE, clears every bus so the next frame starts fresh.
// writes made after it (e.g. in DRAW) survive until the *next* frame's
// POST_UPDATE, so the rest of this frame and the next frame's
// PRE_UPDATE/UPDATE systems still read them — but the next frame's DRAW
// never does, POST_UPDATE gets there first
signal_system :: proc() {
	for _, e in buses {
		e.clear(e.bus)
	}
}
