package netplugin

import "core:fmt"
import netlib "core:net"
import ecs "../../src"

// ---- configuration -------------------------------------------------------

Role :: enum { Server, Client }

Config :: struct {
	role:   Role,
	host:   string,
	port:   int,
}

@(private)
config: Config

configure :: proc(cfg: Config) {
	config = cfg
}

is_server :: proc() -> bool { return config.role == .Server }
is_client :: proc() -> bool { return config.role == .Client }

// ---- component (lives in the plugin, not in src/) ------------------------

// marks an entity as replicated over the network. the net plugin syncs all
// registered (replicable) components on this entity between server and
// clients automatically.
Networked :: struct {
	id:    u32,
	owner: u32,
}

// ---- replicated component registry --------------------------------------
// any component type can be replicated by registering serialize/deserialize
// procs. Transform is registered automatically. Register your own in a
// startup system or plugin:
//
//   net.register_replicated(MyComp, serialize_mycomp, deserialize_mycomp)

Replicator :: struct {
	type_id:    typeid,
	serialize:   proc(world: ^ecs.World, entity: ecs.Entity, buf: ^[dynamic]u8) -> int,
	deserialize: proc(world: ^ecs.World, entity: ecs.Entity, data: []u8, off: ^int),
}

@(private)
replicated: [dynamic]Replicator

register_replicated :: proc(
	type_id: typeid,
	serialize: proc(world: ^ecs.World, entity: ecs.Entity, buf: ^[dynamic]u8) -> int,
	deserialize: proc(world: ^ecs.World, entity: ecs.Entity, data: []u8, off: ^int),
) {
	for r in replicated {
		if r.type_id == type_id { return } // already registered
	}
	append(&replicated, Replicator{type_id = type_id, serialize = serialize, deserialize = deserialize})
}

// default Transform serializer
serialize_transform :: proc(world: ^ecs.World, entity: ecs.Entity, buf: ^[dynamic]u8) -> int {
	t, ok := ecs.try_get_component(world, entity, ecs.Transform)
	if !ok { return 0 }
	bits := transmute(u32)t.translation.x
	for i in 0 ..< 4 { append(buf, u8(bits >> (u32(i)*8))) }
	bits = transmute(u32)t.translation.y
	for i in 0 ..< 4 { append(buf, u8(bits >> (u32(i)*8))) }
	bits = transmute(u32)t.rotation
	for i in 0 ..< 4 { append(buf, u8(bits >> (u32(i)*8))) }
	return 12
}

deserialize_transform :: proc(world: ^ecs.World, entity: ecs.Entity, data: []u8, off: ^int) {
	t, ok := ecs.try_get_component(world, entity, ecs.Transform)
	if !ok {
		ecs.add_component(world, entity, ecs.Transform{})
		t, _ = ecs.try_get_component(world, entity, ecs.Transform)
	}
	x := transmute(f32)(u32(data[off^]) | (u32(data[off^+1]) << 8) | (u32(data[off^+2]) << 16) | (u32(data[off^+3]) << 24))
	off^ += 4
	y := transmute(f32)(u32(data[off^]) | (u32(data[off^+1]) << 8) | (u32(data[off^+2]) << 16) | (u32(data[off^+3]) << 24))
	off^ += 4
	rot := transmute(f32)(u32(data[off^]) | (u32(data[off^+1]) << 8) | (u32(data[off^+2]) << 16) | (u32(data[off^+3]) << 24))
	off^ += 4
	t.translation.x = x
	t.translation.y = y
	t.rotation = rot
}

// ---- state --------------------------------------------------------------

@(private)
socket: netlib.UDP_Socket

@(private)
client_endpoints: [dynamic]netlib.Endpoint

@(private)
client_id: u32

@(private)
next_net_id: u32 = 1

@(private)
net_to_entity: map[u32]ecs.Entity

@(private)
entity_to_net: map[ecs.Entity]u32

@(private)
connected: bool

@(private)
server_endpoint: netlib.Endpoint

@(private)
tick_counter: int

// packet tags
PACKET_SNAPSHOT :: u8(1)
PACKET_INPUT    :: u8(2)

// ---- helpers ------------------------------------------------------------

@(private)
write_u32 :: proc(buf: ^[dynamic]u8, v: u32) {
	append(buf, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))
}

@(private)
write_f32 :: proc(buf: ^[dynamic]u8, v: f32) {
	bits := transmute(u32)v
	write_u32(buf, bits)
}

@(private)
read_u32 :: proc(data: []u8, off: ^int) -> u32 {
	v := u32(data[off^]) | (u32(data[off^+1]) << 8) | (u32(data[off^+2]) << 16) | (u32(data[off^+3]) << 24)
	off^ += 4
	return v
}

@(private)
read_f32 :: proc(data: []u8, off: ^int) -> f32 {
	bits := read_u32(data, off)
	return transmute(f32)bits
}

@(private)
find_client :: proc(ep: netlib.Endpoint) -> int {
	for i in 0 ..< len(client_endpoints) {
		if client_endpoints[i] == ep {
			return i
		}
	}
	return -1
}

// ---- server -------------------------------------------------------------

@(private)
server_init :: proc() {
	addr, _ := netlib.parse_endpoint(fmt.tprintf("0.0.0.0:%d", config.port))
	s, err := netlib.make_bound_udp_socket(addr.address, config.port)
	if err != nil {
		fmt.println("net: server bind failed:", err)
		return
	}
	socket = s
	netlib.set_blocking(socket, false)
	fmt.println("net: server listening on port", config.port)
}

@(private)
server_update :: proc(world: ^ecs.World) {
	// assign net ids to newly spawned Networked entities
	ents := ecs.slice_entity(world, Networked)
	for i in 0 ..< len(ents) {
		n := &ecs.slice(world, Networked)[i]
		if n.id == 0 {
			next_net_id += 1
			n.id = next_net_id
			n.owner = 0
			entity_to_net[ents[i]] = n.id
			net_to_entity[n.id] = ents[i]
		}
	}

	// receive packets (non-blocking)
	buf: [1024]byte
	for {
		n, from, err := netlib.recv_udp(socket, buf[:])
		if err != nil || n <= 0 {
			break
		}
		data := buf[:n]
		if find_client(from) == -1 {
			append(&client_endpoints, from)
			fmt.println("net: client connected")
		}
		if len(data) > 0 && data[0] == PACKET_INPUT {
			off := 1
			nid := read_u32(data, &off)
			owner := read_u32(data, &off)
			x := read_f32(data, &off)
			y := read_f32(data, &off)
			rot := read_f32(data, &off)
			if nid == 0 {
				// spawn request from a client
				next_net_id += 1
				nid = next_net_id
				ent := ecs.spawn_entity(world)
				ecs.add_component(world, ent, Networked{id = nid, owner = owner})
				ecs.add_component(world, ent, ecs.Transform{translation = {x, y}, rotation = rot})
				net_to_entity[nid] = ent
				entity_to_net[ent] = nid
			} else {
				ent, ok := net_to_entity[nid]
				if !ok {
					ent = ecs.spawn_entity(world)
					ecs.add_component(world, ent, Networked{id = nid, owner = owner})
					ecs.add_component(world, ent, ecs.Transform{translation = {x, y}, rotation = rot})
					net_to_entity[nid] = ent
					entity_to_net[ent] = nid
				} else {
					// only apply input for client-owned entities
					if n2, ok2 := ecs.try_get_component(world, ent, Networked); ok2 && n2.owner == owner && owner != 0 {
						if t, ok3 := ecs.try_get_component(world, ent, ecs.Transform); ok3 {
							t.translation = {x, y}
							t.rotation = rot
						}
					}
				}
			}
		}
	}

	// broadcast snapshot (throttled to 20 Hz)
	if tick_counter % 3 != 0 {
		return
	}
	ents2 := ecs.slice_entity(world, Networked)
	sbuf: [dynamic]u8
	write_u32(&sbuf, u32(len(ents2)))
	for i in 0 ..< len(ents2) {
		n := ecs.slice(world, Networked)[i]
		ent := ents2[i]
		write_u32(&sbuf, n.id)
		write_u32(&sbuf, n.owner)
		// serialize all registered components that the entity has
		// (we serialize all registered types; missing ones write a 0 flag)
		for r in replicated {
			start := len(sbuf)
			n := r.serialize(world, ent, &sbuf)
			if n > 0 {
				// prepend a present flag + length before the data: rebuild
				// We already appended data; insert flag+length at start.
				// Simpler: rewrite: remove appended data, write flag, length, data.
				data := sbuf[start:]
				// drop the just-written bytes
				resize(&sbuf, start)
				append(&sbuf, u8(1))
				write_u32(&sbuf, u32(n))
				// re-serialize
				r.serialize(world, ent, &sbuf)
			} else {
				append(&sbuf, u8(0))
			}
		}
	}
	// prepend tag
	tagged: [dynamic]u8
	append(&tagged, PACKET_SNAPSHOT)
	for b in sbuf { append(&tagged, b) }
	delete(sbuf)

	for i in 0 ..< len(client_endpoints) {
		netlib.send_udp(socket, tagged[:], client_endpoints[i])
	}
	delete(tagged)
}

// ---- client -------------------------------------------------------------

@(private)
client_init :: proc() {
	s, err := netlib.make_unbound_udp_socket(.IP4)
	if err != nil {
		fmt.println("net: client socket failed:", err)
		return
	}
	socket = s
	netlib.set_blocking(socket, false)
	ep, ok := netlib.parse_endpoint(fmt.tprintf("%s:%d", config.host, config.port))
	if !ok {
		fmt.println("net: bad host")
		return
	}
	server_endpoint = ep
	fmt.println("net: client targeting", config.host, config.port)
	connected = false
	client_id = 1
}

@(private)
client_update :: proc(world: ^ecs.World) {
	// receive
	buf: [1024]byte
	for {
		n, from, err := netlib.recv_udp(socket, buf[:])
		if err != nil || n <= 0 {
			break
		}
		data := buf[:n]
		if len(data) > 0 && data[0] == PACKET_SNAPSHOT {
			connected = true
			off := 1
			count := read_u32(data, &off)
			for _ in 0 ..< count {
				nid := read_u32(data, &off)
				owner := read_u32(data, &off)
				ent, ok := net_to_entity[nid]
				if !ok {
					ent = ecs.spawn_entity(world)
					ecs.add_component(world, ent, Networked{id = nid, owner = owner})
					net_to_entity[nid] = ent
				} else {
					if n2, ok2 := ecs.try_get_component(world, ent, Networked); ok2 {
						n2.owner = owner
					}
				}
				for r in replicated {
					present := data[off]
					off += 1
					if present == 1 {
						dlen := read_u32(data, &off)
						sub_off := 0
						sub := data[off:off+int(dlen)]
						r.deserialize(world, ent, sub, &sub_off)
						off += int(dlen)
					}
				}
			}
		}
	}

	// retry until connected
	if !connected {
		ping: [dynamic]u8
		append(&ping, u8(0))
		netlib.send_udp(socket, ping[:], server_endpoint)
		delete(ping)
	}

	// throttle sends to 20 Hz
	if tick_counter % 3 != 0 {
		return
	}

	// spawn request if we don't own an entity yet
	has_owned := false
	for i in 0 ..< len(ecs.slice(world, Networked)) {
		if ecs.slice(world, Networked)[i].owner == client_id && client_id != 0 {
			has_owned = true
		}
	}
	if !has_owned && client_id != 0 {
		buf0: [dynamic]u8
		append(&buf0, PACKET_INPUT)
		write_u32(&buf0, 0)
		write_u32(&buf0, client_id)
		write_f32(&buf0, 400)
		write_f32(&buf0, 400)
		write_f32(&buf0, 0)
		netlib.send_udp(socket, buf0[:], server_endpoint)
		delete(buf0)
	}

	// send own player transform
	for i in 0 ..< len(ecs.slice(world, Networked)) {
		n := ecs.slice(world, Networked)[i]
		if n.owner == client_id && client_id != 0 {
			ent := ecs.slice_entity(world, Networked)[i]
			t, ok := ecs.try_get_component(world, ent, ecs.Transform)
			if !ok { continue }
			buf2: [dynamic]u8
			append(&buf2, PACKET_INPUT)
			write_u32(&buf2, n.id)
			write_u32(&buf2, n.owner)
			write_f32(&buf2, t.translation.x)
			write_f32(&buf2, t.translation.y)
			write_f32(&buf2, t.rotation)
			netlib.send_udp(socket, buf2[:], server_endpoint)
			delete(buf2)
		}
	}
}

// ---- auto (inferred) replication -----------------------------------------
// for flat, value-type components, the engine can infer serialization by
// copying the struct's raw bytes — no hand-written procs needed.
// usage: net.replicate(MyComp)  (or net.register_replicated_auto(MyComp))

auto_serialize :: proc($T: typeid, world: ^ecs.World, entity: ecs.Entity, buf: ^[dynamic]u8) -> int {
	comp, ok := ecs.try_get_component(world, entity, T)
	if !ok { return 0 }
	size := size_of(T)
	ptr := cast([^]u8)comp
	for i in 0 ..< size {
		append(buf, ptr[i])
	}
	return size
}

auto_deserialize :: proc($T: typeid, world: ^ecs.World, entity: ecs.Entity, data: []u8, off: ^int) {
	comp, ok := ecs.try_get_component(world, entity, T)
	if !ok {
		ecs.add_component(world, entity, T{})
		comp, _ = ecs.try_get_component(world, entity, T)
	}
	size := size_of(T)
	ptr := cast([^]u8)comp
	for i in 0 ..< size {
		ptr[i] = data[off^ + i]
	}
	off^ += size
}

register_replicated_auto :: proc($T: typeid) {
	ser :: proc(world: ^ecs.World, entity: ecs.Entity, buf: ^[dynamic]u8) -> int {
		return auto_serialize(T, world, entity, buf)
	}
	deser :: proc(world: ^ecs.World, entity: ecs.Entity, data: []u8, off: ^int) {
		auto_deserialize(T, world, entity, data, off)
	}
	register_replicated(typeid_of(T), ser, deser)
}

// convenience alias
replicate :: proc($T: typeid) {
	register_replicated_auto(T)
}

// ---- plugin -------------------------------------------------------------

@(private)
net_update :: proc(world: ^ecs.World) {
	tick_counter += 1
	if config.role == .Server {
		server_update(world)
	} else {
		client_update(world)
	}
}

@(private)
net_init :: proc() {
	// register Transform as a replicated component by default
	register_replicated(typeid_of(ecs.Transform), serialize_transform, deserialize_transform)
	if config.role == .Server {
		server_init()
	} else {
		client_init()
	}
}

@(private)
net_shutdown :: proc() {}

NetPlugin :: proc(app: ^ecs.App) {
	ecs.init_system_set(app, "startup", "net_init", ecs.before("default"))
	ecs.add_system(app, "net_init", net_init)
	ecs.add_system(app, "update", net_update)
	ecs.add_system(app, "destroy", net_shutdown)
}