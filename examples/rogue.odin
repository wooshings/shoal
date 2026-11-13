package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:math/rand"
import ecs "../src"
import term "../plugins/terminal"

// ---- map -----------------------------------------------------------------

MAP_W :: 80
MAP_H :: 24
MAX_ROWS :: 120 // row pool: enough rows to draw the map scaled to a tall terminal
MAX_MONSTERS :: 40
MAX_ITEMS :: 40

Tile :: enum { Wall, Floor, Corridor, Door, Stairs }

tile_char :: proc(t: Tile) -> rune {
	switch t {
	case .Wall:     return '#'
	case .Floor:    return '.'
	case .Corridor: return '.'
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
row_entities: [MAX_ROWS]ecs.Entity

// scaled-view cache: the zoomed row strings, rebuilt only when the terminal
// size (or the level) changes
scaled_text:  [MAX_ROWS]string
scaled_y:     [MAX_ROWS]int
scaled_z:     f32
scaled_tw:    int
scaled_th:    int
scaled_valid: bool

game_over: bool

// combat bookkeeping
turn_count: int
last_msg:   string

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

// damage roll: 25% chance to miss, otherwise atk-def with 0..2 variance
roll_damage :: proc(atk, def: int) -> int {
	if rr(4) == 0 { return 0 }
	base := atk - def
	if base < 1 { base = 1 }
	return base + rr(3)
}

monster_name :: proc(symbol: rune) -> string {
	switch symbol {
	case 'r': return "rat"
	case 'g': return "goblin"
	case 'o': return "orc"
	case 'T': return "troll"
	}
	return "monster"
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
	last_msg = ""
	scaled_valid = false // the zoomed rows are built from the old level

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
			// deeper levels spawn tougher monsters
			max_kind := 2
			if depth >= 2 { max_kind = 3 }
			if depth >= 3 { max_kind = 4 }
			kind := MonsterKind(rr(max_kind))
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
		last_msg = "you quaff a potion"
	case .Weapon:
		player.atk += 2
		last_msg = "you found a weapon (+2 atk)"
	case .Armor:
		player.def += 1
		last_msg = "you found armor (+1 def)"
	case .Gold:
		player.gold += 10
		last_msg = "you picked up gold"
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
		// player attacks (no guaranteed counterattack — the monster only
		// swings on its own move, and it moves at half player speed)
		dmg := roll_damage(player.atk, monsters[mi].def)
		name := monster_name(monsters[mi].symbol)
		if dmg == 0 {
			last_msg = fmt.tprintf("you miss the %s", name)
		} else {
			monsters[mi].hp -= dmg
			if monsters[mi].hp <= 0 {
				monsters[mi].alive = false
				last_msg = fmt.tprintf("you kill the %s!", name)
			} else {
				last_msg = fmt.tprintf("you hit the %s for %d", name, dmg)
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
		last_msg = fmt.tprintf("you descend to depth %d", player.depth)
	}
}

move_monsters :: proc() {
	if game_over { return }
	turn_count += 1
	// monsters are slower than the player: they act every other turn
	if turn_count % 2 == 0 { return }
	for i in 0 ..< monster_count {
		if !monsters[i].alive { continue }
		m := &monsters[i]
		// adjacent attack?
		if abs(m.x-player.x) <= 1 && abs(m.y-player.y) <= 1 {
			if !(m.x == player.x && m.y == player.y) {
				name := monster_name(m.symbol)
				mdmg := roll_damage(m.atk, player.def)
				if mdmg == 0 {
					last_msg = fmt.tprintf("the %s misses you", name)
				} else {
					player.hp -= mdmg
					if player.hp <= 0 {
						player.hp = 0
						player.alive = false
						game_over = true
						last_msg = "you die..."
					} else {
						last_msg = fmt.tprintf("the %s hits you for %d", name, mdmg)
					}
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

// screen cell at the center of a world tile's zoomed block
tile_to_screen :: proc(wx, wy, z: f32, tw, th: int) -> (int, int) {
	return int((wx + 0.5 - f32(MAP_W) / 2) * z + f32(tw) / 2),
	       int((wy + 0.5 - f32(MAP_H) / 2) * z + f32(th) / 2)
}

sync_render :: proc(world: ^ecs.World) {
	tw, th := term.terminal_size()
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
	// view: the map is a fixed MAP_W x MAP_H grid; scale it to fill the
	// terminal by turning every tile into a zoom-sized block of cells
	cams := ecs.slice(world, term.TerminalCamera)
	if len(cams) > 0 {
		if tw < MAP_W || th < MAP_H {
			// terminal smaller than the map: 1:1, camera follows the player
			scaled_valid = false
			cams[0].x = f32(player.x)
			cams[0].y = f32(player.y)
			cams[0].zoom = 1
			for y in 0 ..< MAX_ROWS {
				rc := ecs.get_component(world, row_entities[y], term.Character)
				if y < MAP_H {
					rc.text = row_text[y]
					rc.x = 0
					rc.y = y
					rc.fg = .White
				} else {
					rc.text = ""
					rc.x = -1
					rc.y = -1
				}
			}
		} else {
			z := min(f32(tw) / f32(MAP_W), f32(th) / f32(MAP_H))
			z = min(z, f32(MAX_ROWS) / f32(MAP_H)) // row pool covers the height
			// identity camera: coords written below are already screen coords
			cams[0].x = f32(tw) / 2
			cams[0].y = f32(th) / 2
			cams[0].zoom = 1

			// rebuild the zoomed rows only when the view (or level) changes
			if !scaled_valid || scaled_z != z || scaled_tw != tw || scaled_th != th {
				scaled_z, scaled_tw, scaled_th = z, tw, th
				scaled_valid = true
				for i in 0 ..< MAX_ROWS {
					if len(scaled_text[i]) > 0 {
						delete(scaled_text[i])
						scaled_text[i] = ""
					}
					scaled_y[i] = -1
				}
				n := 0
				for y in 0 ..< MAP_H {
					sy0 := int((f32(y) - f32(MAP_H) / 2) * z + f32(th) / 2)
					sy1 := int((f32(y + 1) - f32(MAP_H) / 2) * z + f32(th) / 2)
					for sy in sy0 ..< sy1 {
						if n >= MAX_ROWS { break }
						b := strings.builder_make()
						for x in 0 ..< MAP_W {
							c := tile_char(dungeon[y][x])
							sx0 := int((f32(x) - f32(MAP_W) / 2) * z + f32(tw) / 2)
							sx1 := int((f32(x + 1) - f32(MAP_W) / 2) * z + f32(tw) / 2)
							for k in 0 ..< max(sx1 - sx0, 0) {
								strings.write_rune(&b, c)
							}
						}
						scaled_text[n] = strings.to_string(b)
						scaled_y[n] = sy
						n += 1
					}
				}
			}
			for i in 0 ..< MAX_ROWS {
				rc := ecs.get_component(world, row_entities[i], term.Character)
				if scaled_text[i] != "" {
					rc.text = scaled_text[i]
					rc.x = 0
					rc.y = scaled_y[i]
					rc.fg = .White
				} else {
					rc.text = ""
					rc.x = -1
					rc.y = -1
				}
			}
			// entities sit at the center of their tile's zoomed block
			pc.x, pc.y = tile_to_screen(f32(player.x), f32(player.y), z, tw, th)
			for i in 0 ..< MAX_MONSTERS {
				if i < monster_count && monsters[i].alive {
					mc := ecs.get_component(world, monster_entities[i], term.Character)
					mc.x, mc.y = tile_to_screen(f32(monsters[i].x), f32(monsters[i].y), z, tw, th)
				}
			}
			for i in 0 ..< MAX_ITEMS {
				if i < item_count && items[i].active {
					ic := ecs.get_component(world, item_entities[i], term.Character)
					ic.x, ic.y = tile_to_screen(f32(items[i].x), f32(items[i].y), z, tw, th)
				}
			}
		}
	}

	// immediate-mode UI overlay — screen-fixed, stamped on top of the game
	term.ui_begin()
	if game_over {
		term.ui_fill(0, 0, 46, .Red)
		term.ui_label(1, 0, fmt.tprintf(" YOU DIED on depth %d — press R to restart ", player.depth), .White, .Red)
	} else {
		hp := fmt.tprintf(" HP %d/%d ", player.hp, player.maxhp)
		stats := fmt.tprintf(" DEPTH %d   ATK %d   DEF %d   GOLD %d ", player.depth, player.atk, player.def, player.gold)
		term.ui_fill(0, 0, len(hp)+len(stats), .BrightBlack)
		term.ui_label(0, 0, hp, .BrightWhite, .Red)
		term.ui_label(len(hp), 0, stats, .Black, .BrightYellow)
	}
	if last_msg != "" {
		term.ui_label(0, 1, fmt.tprintf(" %s ", last_msg), .Black, .BrightCyan)
	}
	term.ui_label(0, th - 1, "arrows/WASD move   R restart   Q quit", .Cyan)
}

// ---- main ---------------------------------------------------------------

main :: proc() {
	app: ecs.App
	ecs.add_plugin(&app, ecs.HeadlessDefaultPlugin)
	ecs.add_plugin(&app, term.TerminalPlugin)

	ecs.add_system(&app, "startup", proc(world: ^ecs.World) {
		// row entities first (map layer)
		for y in 0 ..< MAX_ROWS {
			e := ecs.spawn_entity(world)
			ecs.add_component(world, e, term.Character{text = "", x = -1, y = -1, fg = .White})
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
		// camera
		cam := ecs.spawn_entity(world)
		ecs.add_component(world, cam, term.TerminalCamera{x = 40, y = 12, zoom = 1})

		generate_level(1)
		sync_render(world)
	})

	ecs.add_system(&app, "update", proc(world: ^ecs.World) {
		if ecs.is_pressed(ecs.Q) {
			fmt.print("\x1b[0m\x1b[?25h\n")
			os.exit(0)
		}
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
