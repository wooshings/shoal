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

client_id :: proc() -> u32 { return my_client_id }

// the replicated entity owned by this client (if any): the entity whose
// Networked.owner matches this client's id. returns (entity, true) on a
// client that has spawned/owns one, (0, false) otherwise. on a server this
// always returns (0, false)
owned_entity :: proc(world: ^ecs.World) -> (ecs.Entity, bool) {
	if config.role != .Client { return 0, false }
	ents := ecs.slice_entity(world, Networked)
	for i in 0 ..< len(ents) {
		if ecs.slice(world, Networked)[i].owner == my_client_id && my_client_id != 0 {
			return ents[i], true
		}
	}
	return 0, false
}

// client: ask the server to spawn (or reuse) an entity owned by this client.
// sends one PACKET_INPUT packet with nid = 0; the server's nid == 0 path is
// idempotent per owner, so repeated calls never spawn duplicates. minimal
// examples use this to obtain an owned entity (the game itself spawns
// players through the netgame PlayerState path and never calls this)
request_spawn :: proc(x, y, rot: f32) {
	if config.role != .Client || my_client_id == 0 { return }
	buf: [dynamic]u8
	append(&buf, PACKET_INPUT)
	write_u32(&buf, 0) // nid = 0: spawn request
	write_u32(&buf, my_client_id)
	write_f32(&buf, x)
	write_f32(&buf, y)
	write_f32(&buf, rot)
	netlib.send_udp(socket, buf[:], server_endpoint)
	delete(buf)
}

// ---- component (lives in the plugin, not in src/) ------------------------

// marks an entity as replicated over the network. the net plugin syncs all
// registered (replicable) components on this entity between server and
// clients automatically.
Networked :: struct {
	id:    u32,
	owner: u32,
}

// signals emitted by the net plugin (read with ecs.read(net.ClientConnected))
ClientConnected    :: struct { id: u32 }
ClientDisconnected :: struct { id: u32 }

// ---- networked signals --------------------------------------------------
// signals (ecs.write/ecs.read) are in-process. register_signal makes a signal
// type travel over the network: write_signal(val) on one peer, read it on
// others via ecs.read(T) (the net plugin re-emits it into the local bus).

NetSignalType :: struct {
	type_id:      typeid,
	read_pending:  proc() -> (rawptr, int, int),
	emit:          proc(data: []u8),
}

@(private)
net_signals: [dynamic]NetSignalType

register_signal :: proc($T: typeid) {
	for ns in net_signals {
		if ns.type_id == typeid_of(T) { return }
	}
	read_pending :: proc() -> (rawptr, int, int) {
		sigs := ecs.read(T)
		if len(sigs) == 0 { return nil, 0, size_of(T) }
		return raw_data(sigs), len(sigs), size_of(T)
	}
	emit :: proc(data: []u8) {
		// guard against a malformed packet handing emit a slice shorter
		// than the signal type
		if len(data) < size_of(T) { return }
		val: T
		ptr := cast([^]u8)&val
		for i in 0 ..< size_of(T) { ptr[i] = data[i] }
		ecs.write(val)
	}
	append(&net_signals, NetSignalType{type_id = typeid_of(T), read_pending = read_pending, emit = emit})
}

// broadcast a signal value to peers
write_signal :: proc(val: $T) {
	idx := -1
	for i in 0 ..< len(net_signals) {
		if net_signals[i].type_id == typeid_of(T) { idx = i; break }
	}
	if idx == -1 { return }

	buf: [dynamic]u8
	v := val
	ptr := cast([^]u8)&v
	append(&buf, PACKET_SIGNAL)
	write_u32(&buf, 1)
	write_u32(&buf, u32(idx))
	write_u32(&buf, u32(size_of(T)))
	for i in 0 ..< size_of(T) { append(&buf, ptr[i]) }
	if config.role == .Server {
		for i in 0 ..< len(client_endpoints) {
			netlib.send_udp(socket, buf[:], client_endpoints[i])
		}
	} else {
		netlib.send_udp(socket, buf[:], server_endpoint)
	}
	delete(buf)
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
	if off^ < 0 || off^ > len(data) - 12 {
		return
	}
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
client_ids: map[netlib.Endpoint]u32

@(private)
next_client_id: u32 = 1

@(private)
my_client_id: u32

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
PACKET_SIGNAL   :: u8(4)
PACKET_WELCOME  :: u8(5)

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
read_u32 :: proc(data: []u8, off: ^int) -> (u32, bool) {
	// a negative offset must fail here: it would otherwise index the slice
	// below (and every later read would pass too, since off^ + 4 grows
	// toward 0 from below)
	if off^ < 0 || off^ > len(data) - 4 {
		return 0, false
	}
	v := u32(data[off^]) | (u32(data[off^+1]) << 8) | (u32(data[off^+2]) << 16) | (u32(data[off^+3]) << 24)
	off^ += 4
	return v, true
}

@(private)
read_f32 :: proc(data: []u8, off: ^int) -> (f32, bool) {
	bits, ok := read_u32(data, off)
	return transmute(f32)bits, ok
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
	err2 := netlib.set_blocking(socket, false)
	client_ids = make(map[netlib.Endpoint]u32)
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
			entity_to_net[ents[i]] = n.id
			net_to_entity[n.id] = ents[i]
		}
	}

	// drain the socket (non-blocking): a frame can carry more than one
	// datagram when several clients are active
	buf: [1024]byte
	for {
		n, from, err := netlib.recv_udp(socket, buf[:])
		if err != nil || n <= 0 {
			break
		}
		data := buf[:n]
		if find_client(from) == -1 {
			append(&client_endpoints, from)
			cid := next_client_id
			next_client_id += 1
			client_ids[from] = cid
			ecs.write(ClientConnected{id = cid})
			fmt.println("net: client connected, id", cid)
			wbuf: [dynamic]u8
			append(&wbuf, PACKET_WELCOME)
			write_u32(&wbuf, cid)
			netlib.send_udp(socket, wbuf[:], from)
			delete(wbuf)
		}
		if len(data) > 0 && data[0] == 3 { // disconnect
			if cid, ok := client_ids[from]; ok {
				ecs.write(ClientDisconnected{id = cid})
				delete_key(&client_ids, from)
				for i := 0; i < len(client_endpoints); i += 1 {
					if client_endpoints[i] == from {
						ordered_remove(&client_endpoints, i)
						break
					}
				}
				fmt.println("net: client disconnected, id", cid)
			}
		} else if len(data) > 0 && data[0] == PACKET_SIGNAL {
			off := 1
			count, ok := read_u32(data, &off)
			if ok {
				for _ in 0 ..< count {
					idx, ok1 := read_u32(data, &off)
					dlen, ok2 := read_u32(data, &off)
					if !ok1 || !ok2 {
						break
					}
					// unsigned bounds check: a length field >= 2^31 (or any
					// value past the buffer) must never slice or advance
					// off into negative territory
					if u64(dlen) > u64(len(data) - off) {
						break
					}
					if idx >= u32(len(net_signals)) {
						off += int(dlen)
						continue
					}
					net_signals[idx].emit(data[off:off+int(dlen)])
					// rebroadcast to other clients
					fwd: [dynamic]u8
					append(&fwd, PACKET_SIGNAL)
					write_u32(&fwd, 1)
					write_u32(&fwd, idx)
					write_u32(&fwd, dlen)
					for i in 0 ..< int(dlen) { append(&fwd, data[off+i]) }
					for i in 0 ..< len(client_endpoints) {
						if client_endpoints[i] != from {
							netlib.send_udp(socket, fwd[:], client_endpoints[i])
						}
					}
					delete(fwd)
					off += int(dlen)
				}
			}
		} else if len(data) > 0 && data[0] == PACKET_INPUT {
			off := 1
			nid, ok_nid := read_u32(data, &off)
			owner, ok_owner := read_u32(data, &off)
			x, ok_x := read_f32(data, &off)
			y, ok_y := read_f32(data, &off)
			rot, ok_rot := read_f32(data, &off)
			if !ok_nid || !ok_owner || !ok_x || !ok_y || !ok_rot {
				continue
			}
			if nid == 0 {
				// spawn request. idempotent per owner: reuse an existing
				// Networked entity with the same owner instead of spawning
				// another one, so repeated requests never accumulate ghosts
				if owner != 0 {
					all := ecs.slice_entity(world, Networked)
					reused := false
					for i in 0 ..< len(all) {
						n := ecs.slice(world, Networked)[i]
						if n.owner == owner {
							if t, ok := ecs.try_get_component(world, all[i], ecs.Transform); ok {
								t.translation = {x, y}
								t.rotation = rot
							}
							reused = true
							break
						}
					}
					if reused { continue }
				}
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
		ecs.try_get_component(world, ent, ecs.Transform)
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
	// 0 is the "unknown" sentinel everywhere else (client_id, owned_entity,
	// the game's owner comparisons) — seed it that way until WELCOME
	my_client_id = 0
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
		if len(data) > 0 && data[0] == PACKET_SIGNAL {
			off := 1
			count, ok := read_u32(data, &off)
			if ok {
				for _ in 0 ..< count {
					idx, ok1 := read_u32(data, &off)
					dlen, ok2 := read_u32(data, &off)
					if !ok1 || !ok2 {
						break
					}
					// unsigned bounds check: same rule as the server path
					if u64(dlen) > u64(len(data) - off) {
						break
					}
					if idx >= u32(len(net_signals)) {
						off += int(dlen)
						continue
					}
					net_signals[idx].emit(data[off:off+int(dlen)])
					off += int(dlen)
				}
			}
		} else if len(data) > 0 && data[0] == PACKET_WELCOME {
			off := 1
			cid, ok := read_u32(data, &off)
			if ok {
				my_client_id = cid
				if !connected {
					connected = true
					ecs.write(ClientConnected{id = my_client_id})
				}
				fmt.println("net: welcome, client id", my_client_id)
			}
		} else if len(data) > 0 && data[0] == PACKET_SNAPSHOT {
			connected = true
			off := 1
			count, ok := read_u32(data, &off)
			if ok {
				snapshot: for _ in 0 ..< count {
					nid, ok_nid := read_u32(data, &off)
					owner, ok_owner := read_u32(data, &off)
					if !ok_nid || !ok_owner {
						break snapshot
					}
					ent, known := net_to_entity[nid]
					if !known {
						ent = ecs.spawn_entity(world)
						ecs.add_component(world, ent, Networked{id = nid, owner = owner})
						net_to_entity[nid] = ent
					} else {
						if n2, has_n := ecs.try_get_component(world, ent, Networked); has_n {
							n2.owner = owner
						}
					}
					for r in replicated {
						if off >= len(data) {
							break snapshot
						}
						present := data[off]
						off += 1
						if present == 1 {
							dlen, ok3 := read_u32(data, &off)
							if !ok3 || u64(dlen) > u64(len(data) - off) {
								break snapshot
							}
							sub_off := 0
							sub := data[off:off+int(dlen)]
							r.deserialize(world, ent, sub, &sub_off)
							off += int(dlen)
						}
					}
				}
			}
		}
	}

	// retry until connected
	if !connected {
		ping: [dynamic]u8
		append(&ping, u8(0))
		bw, err := netlib.send_udp(socket, ping[:], server_endpoint)
		_ = bw; _ = err
		delete(ping)
	}

	// throttle sends to 20 Hz
	if tick_counter % 3 != 0 {
		return
	}

	// send own player transform
	for i in 0 ..< len(ecs.slice(world, Networked)) {
		n := ecs.slice(world, Networked)[i]
		if n.owner == my_client_id && my_client_id != 0 {
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
	size := size_of(T)
	if off^ < 0 || off^ > len(data) - size {
		return
	}
	comp, ok := ecs.try_get_component(world, entity, T)
	if !ok {
		ecs.add_component(world, entity, T{})
		comp, _ = ecs.try_get_component(world, entity, T)
	}
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
net_shutdown :: proc() {
	if config.role == .Client && connected {
		buf: [dynamic]u8
		append(&buf, u8(3))
		netlib.send_udp(socket, buf[:], server_endpoint)
		delete(buf)
	}
	delete(client_ids)
}

NetPlugin :: proc(app: ^ecs.App) {
	ecs.init_system_set(app, "startup", "net_init", ecs.before("default"))
	ecs.add_system(app, "net_init", net_init)
	ecs.add_system(app, "update", net_update)
	ecs.add_system(app, "destroy", net_shutdown)
}