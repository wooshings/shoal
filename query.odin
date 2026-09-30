package shoal

Query :: struct {
	with: [dynamic]struct{},
}

query :: proc(app: ^App, query: Query) {
	for e in app.entities {
	}
}
