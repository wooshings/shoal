package shoal

@(private)
signal_buffer_b: [dynamic]string
@(private)
signal_buffer_a: [dynamic]string

write :: proc(name: string) {
	append(&signal_buffer_b, name)
}

read :: proc(name: string) -> bool {
	for s in signal_buffer_a {
		if s == name {return true}
	}
	for s in signal_buffer_b {
		if s == name {return true}
	}
	return false
}

signal_system :: proc() {
	signal_buffer_a = signal_buffer_b
	clear(&signal_buffer_b)
}
