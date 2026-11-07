package netplugin

import "core:fmt"
import "core:mem"
import netlib "core:net"
import ecs "../../src"

// ---- component -----------------------------------------------------------

// marks an entity as replicated over the network. the net plugin syncs
// the entity's Transform between server and clients automatically.
// net_id is assigned by the server; owner is the client id that controls
// it (0 = server-owned).
Networked :: struct {
	id:    u32,
	owner: u32,
}

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

// ---- state --------------------------------------------------------------

@(private)
socket: netlib.UDP_Socket

@(private)
server_endpoint: netlib.Endpoint

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

	// receive packets (non-blocking via short timeout)
	buf: [1024]byte
	for {
		n, from, err := netlib.recv_udp(socket, buf[:])
		if err != nil || n <= 0 {
			break
		}
		data := buf[:n]
		if len(data) > 0 && data[0] == PACKET_INPUT {
			off := 1
			nid := read_u32(data, &off)
			x := read_f32(data, &off)
			y := read_f32(data, &off)
			rot := read_f32(data, &off)
			if ent, ok := net_to_entity[nid]; ok {
				if t, ok2 := ecs.try_get_component(world, ent, ecs.Transform); ok2 {
					t.translation = {x, y}
					t.rotation = rot
				}
			}
			// register new client endpoint
			if find_client(from) == -1 {
				append(&client_endpoints, from)
				fmt.println("net: client connected")
			}
		}
	}

	// broadcast snapshot
	sbuf: [dynamic]u8
	write_u32(&sbuf, u32(len(ents)))
	for i in 0 ..< len(ents) {
		n := ecs.slice(world, Networked)[i]
		ent := ents[i]
		t, _ := ecs.try_get_component(world, ent, ecs.Transform)
		write_u32(&sbuf, n.id)
		write_f32(&sbuf, t.translation.x)
		write_f32(&sbuf, t.translation.y)
		write_f32(&sbuf, t.rotation)
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
	addr, _ := netlib.parse_endpoint(fmt.tprintf("0.0.0.0:0"))
	s, err := netlib.make_unbound_udp_socket(.IP4)
	if err != nil {
		fmt.println("net: client socket failed:", err)
		return
	}
	socket = s
	// resolve server endpoint
	ep, ok := netlib.parse_endpoint(fmt.tprintf("%s:%d", config.host, config.port))
	if !ok {
		fmt.println("net: bad host")
		return
	}
	server_endpoint = ep
	fmt.println("net: client targeting", config.host, config.port)
	connected = true
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
			off := 1
			count := read_u32(data, &off)
			for _ in 0 ..< count {
				nid := read_u32(data, &off)
				x := read_f32(data, &off)
				y := read_f32(data, &off)
				rot := read_f32(data, &off)
				ent, ok := net_to_entity[nid]
				if !ok {
					ent = ecs.spawn_entity(world)
					ecs.add_component(world, ent, Networked{id = nid, owner = 0})
					ecs.add_component(world, ent, ecs.Transform{translation = {x, y}, rotation = rot})
					net_to_entity[nid] = ent
				} else {
					if t, ok2 := ecs.try_get_component(world, ent, ecs.Transform); ok2 {
						t.translation = {x, y}
						t.rotation = rot
					}
				}
			}
		}
	}

	// send own player transform (entities we own)
	for i in 0 ..< len(ecs.slice(world, Networked)) {
		n := ecs.slice(world, Networked)[i]
		if n.owner == client_id && client_id != 0 {
			ent := ecs.slice_entity(world, Networked)[i]
			t, _ := ecs.try_get_component(world, ent, ecs.Transform)
			buf2: [dynamic]u8
			append(&buf2, PACKET_INPUT)
			write_u32(&buf2, n.id)
			write_f32(&buf2, t.translation.x)
			write_f32(&buf2, t.translation.y)
			write_f32(&buf2, t.rotation)
			netlib.send_udp(socket, buf2[:], server_endpoint)
			delete(buf2)
		}
	}
}

// ---- plugin -------------------------------------------------------------

@(private)
net_update :: proc(world: ^ecs.World) {
	if config.role == .Server {
		server_update(world)
	} else {
		client_update(world)
	}
}

@(private)
net_init :: proc() {
	if config.role == .Server {
		server_init()
	} else {
		client_init()
	}
}

@(private)
net_shutdown :: proc() {
	// nothing special
}



// role helpers for game code that needs to branch (e.g. headless vs windowed)
is_server :: proc() -> bool { return config.role == .Server }
is_client :: proc() -> bool { return config.role == .Client }

NetPlugin :: proc(app: ^ecs.App) {
	ecs.init_system_set(app, "startup", "net_init", ecs.before("default"))
	ecs.add_system(app, "net_init", net_init)
	ecs.add_system(app, "update", net_update)
	ecs.add_system(app, "destroy", net_shutdown)
}
