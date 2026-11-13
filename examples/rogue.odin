package main

import "core:fmt"
import "core:strings"
import "core:math/rand"
import ecs "../src"
import term "../plugins/terminal"

// ---- map -----------------------------------------------------------------

MAP_W :: 80
MAP_H :: 24
MAX_MONSTERS :: 40
MAX_ITEMS :: 40

Tile :: enum { Wall, Floor, Corridor, Door, Stairs }

tile_char :: proc(t: Tile) -> rune {
	switch t {
	case .Wall:     return '#'
	case .Floor:    return '.'
	case .Corridor: return '#'
	case .Door:     return '+'
	case .Stairs:   return '>'
	}
	return ' '
}

Rect :: struct { x, y, w, h: int }

dungeon: [MAP_H][MAP_W]Tile
row_text: [MAP_H]string

// ---- game state ----------------------------------------------------------

Player :: struct {
	x, y: int,
	hp, maxhp: int,
	atk, def: int,
	gold: int,
	depth: int,
	alive: bool,
}

MonsterKind :: enum { Rat, Goblin, Orc, Troll }

Monster :: struct {
	x, y: int,
	hp, atk, def: int,
	symbol: rune,
	alive: bool,
}

ItemKind :: enum { Potion, Weapon, Armor, Gold }

Item :: struct {
	x, y: int,
	kind: ItemKind,
	active: bool,
}

player: Player
monsters: [MAX_MONSTERS]Monster
monster_count: int
items: [MAX_ITEMS]Item
item_count: int

// ---- entities -----------------------------------------------------------

player_entity: ecs.Entity
monster_entities: [MAX_MONSTERS]ecs.Entity
item_entities: [MAX_ITEMS]ecs.Entity
row_entities: [MAP_H]ecs.Entity
status_entity: ecs.Entity

game_over: bool

// ---- helpers ------------------------------------------------------------

rng_seeded: bool

rr :: proc(n: int) -> int {
	if !rng_seeded {
		rand.reset(u64(12345))
		rng_seeded = true
	}
	if n <= 0 { return 0 }
	return rand.int_max(n)
}

sign :: proc(v: int) -> int {
	if v > 0 { return 1 }
	if v < 0 { return -1 }
	return 0
}

// ---- level generation ---------------------------------------------------

generate_level :: proc(depth: int) {
	// reset
	for y in 0 ..< MAP_H {
		for x in 0 ..< MAP_W {
			dungeon[y][x] = .Wall
		}
	}
	monster_count = 0
	item_count = 0
	player.alive = true
	game_over = false

	rooms := [dynamic]Rect{}
	defer delete(rooms)

	for len(rooms) < 8 {
		w := rr(6) + 4
		h := rr(4) + 3
		x := rr(MAP_W - w - 2) + 1
		y := rr(MAP_H - h - 2) + 1
		ok := true
		for r in rooms {
			if x-1 <= r.x+r.w && x+w+1 >= r.x && y-1 <= r.y+r.h && y+h+1 >= r.y {
				ok = false
				break
			}
		}
		if !ok { continue }
		for yy in y ..< y+h {
			for xx in x ..< x+w {
				dungeon[yy][xx] = .Floor
			}
		}
		append(&rooms, Rect{x = x, y = y, w = w, h = h})
	}

	// connect rooms
	for i in 1 ..< len(rooms) {
		prev := rooms[i-1]
		cur := rooms[i]
		x1 := prev.x + prev.w / 2
		y1 := prev.y + prev.h / 2
		x2 := cur.x + cur.w / 2
		y2 := cur.y + cur.h / 2
		for x := min(x1, x2); x <= max(x1, x2); x += 1 {
			dungeon[y1][x] = .Corridor
		}
		for y := min(y1, y2); y <= max(y1, y2); y += 1 {
			dungeon[y][x2] = .Corridor
		}
	}

	// stairs in last room
	last := rooms[len(rooms)-1]
	sx := last.x + last.w / 2
	sy := last.y + last.h / 2
	dungeon[sy][sx] = .Stairs

	// player in first room
	first := rooms[0]
	player.x = first.x + first.w / 2
	player.y = first.y + first.h / 2
	player.depth = depth
	if depth == 1 {
		player.hp = 30
		player.maxhp = 30
		player.atk = 5
		player.def = 1
		player.gold = 0
	} else {
		player.maxhp += 5
		player.hp = player.maxhp
		player.atk += 1
	}

	// monsters + items in other rooms
	for ri in 1 ..< len(rooms) {
		r := rooms[ri]
		// monsters
		nm := rr(3) + 1
		for m in 0 ..< nm {
			if monster_count >= MAX_MONSTERS { break }
			mx := r.x + rr(r.w)
			my := r.y + rr(r.h)
			if mx == player.x && my == player.y { continue }
			if dungeon[my][mx] != .Floor { continue }
			kind := MonsterKind(rr(4))
			mon: Monster
			mon.x = mx
			mon.y = my
			mon.alive = true
			switch kind {
			case .Rat:
				mon.symbol = 'r'
				mon.hp = 4 + depth
				mon.atk = 2 + depth / 2
				mon.def = 0
			case .Goblin:
				mon.symbol = 'g'
				mon.hp = 8 + depth * 2
				mon.atk = 4 + depth / 2
				mon.def = 1
			case .Orc:
				mon.symbol = 'o'
				mon.hp = 14 + depth * 2
				mon.atk = 6 + depth
				mon.def = 2
			case .Troll:
				mon.symbol = 'T'
				mon.hp = 22 + depth * 3
				mon.atk = 9 + depth
				mon.def = 3
			}
			monsters[monster_count] = mon
			monster_count += 1
		}
		// items
		ni := rr(3)
		for it in 0 ..< ni {
			if item_count >= MAX_ITEMS { break }
			ix := r.x + rr(r.w)
			iy := r.y + rr(r.h)
			if ix == player.x && iy == player.y { continue }
			if dungeon[iy][ix] != .Floor { continue }
			kind := ItemKind(rr(4))
			items[item_count] = Item{x = ix, y = iy, kind = kind, active = true}
			item_count += 1
		}
	}

	// build row text
	for y in 0 ..< MAP_H {
		b := strings.builder_make()
		for x in 0 ..< MAP_W {
			strings.write_rune(&b, tile_char(dungeon[y][x]))
		}
		row_text[y] = strings.to_string(b)
	}
}

// ---- logic --------------------------------------------------------------

monster_at :: proc(x, y: int) -> int {
	for i in 0 ..< monster_count {
		if monsters[i].alive && monsters[i].x == x && monsters[i].y == y {
			return i
		}
	}
	return -1
}

item_at :: proc(x, y: int) -> int {
	for i in 0 ..< item_count {
		if items[i].active && items[i].x == x && items[i].y == y {
			return i
		}
	}
	return -1
}

pickup_item :: proc(idx: int) {
	it := &items[idx]
	switch it.kind {
	case .Potion:
		player.hp += 20
		if player.hp > player.maxhp { player.hp = player.maxhp }
	case .Weapon:
		player.atk += 2
	case .Armor:
		player.def += 1
	case .Gold:
		player.gold += 10
	}
	it.active = false
}

try_move_player :: proc(dx, dy: int) {
	if game_over { return }
	nx := player.x + dx
	ny := player.y + dy
	if nx < 0 || ny < 0 || nx >= MAP_W || ny >= MAP_H { return }
	if dungeon[ny][nx] == .Wall { return }
	mi := monster_at(nx, ny)
	if mi >= 0 {
		// attack
		dmg := player.atk - monsters[mi].def
		if dmg < 1 { dmg = 1 }
		monsters[mi].hp -= dmg
		if monsters[mi].hp <= 0 {
			monsters[mi].alive = false
		}
		// monster counterattacks if survives
		if monsters[mi].alive {
			mdmg := monsters[mi].atk - player.def
			if mdmg < 1 { mdmg = 1 }
			player.hp -= mdmg
			if player.hp <= 0 {
				player.hp = 0
				player.alive = false
				game_over = true
			}
		}
		return
	}
	player.x = nx
	player.y = ny
	// pickup
	ii := item_at(nx, ny)
	if ii >= 0 {
		pickup_item(ii)
	}
	// stairs
	if dungeon[ny][nx] == .Stairs {
		generate_level(player.depth + 1)
	}
}

move_monsters :: proc() {
	if game_over { return }
	for i in 0 ..< monster_count {
		if !monsters[i].alive { continue }
		m := &monsters[i]
		// adjacent attack?
		if abs(m.x-player.x) <= 1 && abs(m.y-player.y) <= 1 {
			if !(m.x == player.x && m.y == player.y) {
				mdmg := m.atk - player.def
				if mdmg < 1 { mdmg = 1 }
				player.hp -= mdmg
				if player.hp <= 0 {
					player.hp = 0
					player.alive = false
					game_over = true
				}
				continue
			}
		}
		// move toward player
		dx := sign(player.x - m.x)
		dy := sign(player.y - m.y)
		// try x then y
		nx := m.x + dx
		ny := m.y
		if dx != 0 && nx >= 0 && ny >= 0 && nx < MAP_W && ny < MAP_H && dungeon[ny][nx] != .Wall {
			if monster_at(nx, ny) < 0 && !(nx == player.x && ny == player.y) {
				m.x = nx
				continue
			}
		}
		nx = m.x
		ny = m.y + dy
		if dy != 0 && nx >= 0 && ny >= 0 && nx < MAP_W && ny < MAP_H && dungeon[ny][nx] != .Wall {
			if monster_at(nx, ny) < 0 && !(nx == player.x && ny == player.y) {
				m.y = ny
			}
		}
	}
}

// ---- sync render ---------------------------------------------------------

sync_render :: proc(world: ^ecs.World) {
	for y in 0 ..< MAP_H {
		ecs.get_component(world, row_entities[y], term.Character).text = row_text[y]
	}
	// player
	pc := ecs.get_component(world, player_entity, term.Character)
	pc.glyph = '@'
	pc.x = player.x
	pc.y = player.y
	pc.fg = .Yellow
	pc.bold = true
	if !player.alive {
		pc.fg = .Red
	}
	// monsters
	for i in 0 ..< MAX_MONSTERS {
		mc := ecs.get_component(world, monster_entities[i], term.Character)
		if i < monster_count && monsters[i].alive {
			mc.glyph = monsters[i].symbol
			mc.x = monsters[i].x
			mc.y = monsters[i].y
			mc.fg = .Red
			mc.bold = false
		} else {
			mc.x = -1
			mc.y = -1
		}
	}
	// items
	for i in 0 ..< MAX_ITEMS {
		ic := ecs.get_component(world, item_entities[i], term.Character)
		if i < item_count && items[i].active {
			switch items[i].kind {
			case .Potion: ic.glyph = '!'
			case .Weapon: ic.glyph = ')'
			case .Armor:  ic.glyph = ']'
			case .Gold:   ic.glyph = '$'
			}
			ic.x = items[i].x
			ic.y = items[i].y
			ic.fg = .Magenta
			ic.bold = false
		} else {
			ic.x = -1
			ic.y = -1
		}
	}
	// status
	sc := ecs.get_component(world, status_entity, term.Character)
	if game_over {
		sc.text = fmt.tprintf("YOU DIED on depth %d. Press R to restart.", player.depth)
	} else {
		sc.text = fmt.tprintf("Depth %d  HP %d/%d  ATK %d  DEF %d  Gold %d  (arrows move, r restart)", player.depth, player.hp, player.maxhp, player.atk, player.def, player.gold)
	}
	sc.x = 0
	sc.y = MAP_H
	sc.fg = .Cyan
	sc.bold = false

	// camera follows player
	cams := ecs.slice(world, term.TerminalCamera)
	if len(cams) > 0 {
		cams[0].x = f32(player.x)
		cams[0].y = f32(player.y)
	}
}

// ---- main ---------------------------------------------------------------

main :: proc() {
	app: ecs.App
	ecs.add_plugin(&app, ecs.HeadlessDefaultPlugin)
	ecs.add_plugin(&app, term.TerminalPlugin)

	ecs.add_system(&app, "startup", proc(world: ^ecs.World) {
		// row entities first (map layer)
		for y in 0 ..< MAP_H {
			e := ecs.spawn_entity(world)
			ecs.add_component(world, e, term.Character{text = "", x = 0, y = y, fg = .White})
			row_entities[y] = e
		}
		// player
		player_entity = ecs.spawn_entity(world)
		ecs.add_component(world, player_entity, term.Character{glyph = '@', x = 0, y = 0, fg = .Yellow, bold = true})
		// monsters
		for i in 0 ..< MAX_MONSTERS {
			e := ecs.spawn_entity(world)
			ecs.add_component(world, e, term.Character{glyph = ' ', x = -1, y = -1, fg = .Red})
			monster_entities[i] = e
		}
		// items
		for i in 0 ..< MAX_ITEMS {
			e := ecs.spawn_entity(world)
			ecs.add_component(world, e, term.Character{glyph = ' ', x = -1, y = -1, fg = .Magenta})
			item_entities[i] = e
		}
		// status line
		status_entity = ecs.spawn_entity(world)
		ecs.add_component(world, status_entity, term.Character{text = "", x = 0, y = MAP_H, fg = .Cyan})
		// camera
		cam := ecs.spawn_entity(world)
		ecs.add_component(world, cam, term.TerminalCamera{x = 40, y = 12, zoom = 1})

		generate_level(1)
		sync_render(world)
	})

	ecs.add_system(&app, "update", proc(world: ^ecs.World) {
		if ecs.is_pressed(ecs.R) {
			generate_level(1)
			sync_render(world)
			return
		}
		if game_over {
			sync_render(world)
			return
		}
		dx, dy := 0, 0
		if ecs.is_pressed(ecs.UP) || ecs.is_pressed(ecs.W) { dy = -1 }
		if ecs.is_pressed(ecs.DOWN) || ecs.is_pressed(ecs.S) { dy = 1 }
		if ecs.is_pressed(ecs.LEFT) || ecs.is_pressed(ecs.A) { dx = -1 }
		if ecs.is_pressed(ecs.RIGHT) || ecs.is_pressed(ecs.D) { dx = 1 }
		if dx != 0 || dy != 0 {
			try_move_player(dx, dy)
			if !game_over {
				move_monsters()
			}
		}
		sync_render(world)
	})

	fmt.println("rogue (q to quit)")
	ecs.run_headless(&app)
}
