package shoal

BTStatus :: enum { Success, Failure, Running }

BTNodeKind :: enum { Sequence, Selector, Action }

BTNode :: struct {
	kind:        BTNodeKind,
	name:        string,
	children:    [dynamic]^BTNode,
	callback:    proc(node: ^BTNode, ctx: rawptr) -> BTStatus,
	data:        rawptr,
	running_idx: int, // -1 initially, supports Running resume
}

bt_sequence :: proc(name: string) -> ^BTNode {
	n := new(BTNode)
	n.kind = .Sequence
	n.name = name
	n.children = make([dynamic]^BTNode)
	n.running_idx = -1
	return n
}

bt_selector :: proc(name: string) -> ^BTNode {
	n := new(BTNode)
	n.kind = .Selector
	n.name = name
	n.children = make([dynamic]^BTNode)
	n.running_idx = -1
	return n
}

bt_action :: proc(name: string, callback: proc(node: ^BTNode, ctx: rawptr) -> BTStatus, data: rawptr) -> ^BTNode {
	n := new(BTNode)
	n.kind = .Action
	n.name = name
	n.children = make([dynamic]^BTNode)
	n.callback = callback
	n.data = data
	n.running_idx = -1
	return n
}

bt_add_child :: proc(parent, child: ^BTNode) {
	append(&parent.children, child)
}

bt_tick :: proc(node: ^BTNode, ctx: rawptr, fired: ^string) -> BTStatus {
	switch node.kind {
	case .Sequence:
		start := 0
		if node.running_idx >= 0 && node.running_idx < len(node.children) {
			start = node.running_idx
		}
		for i := start; i < len(node.children); i += 1 {
			s := bt_tick(node.children[i], ctx, fired)
			switch s {
			case .Running:
				node.running_idx = i
				return .Running
			case .Failure:
				node.running_idx = -1
				return .Failure
			case .Success:
				if node.running_idx == i {node.running_idx = -1}
			}
		}
		node.running_idx = -1
		return .Success
	case .Selector:
		start := 0
		if node.running_idx >= 0 && node.running_idx < len(node.children) {
			start = node.running_idx
		}
		for i := start; i < len(node.children); i += 1 {
			s := bt_tick(node.children[i], ctx, fired)
			switch s {
			case .Running:
				node.running_idx = i
				return .Running
			case .Success:
				node.running_idx = -1
				return .Success
			case .Failure:
				if node.running_idx == i {node.running_idx = -1}
			}
		}
		node.running_idx = -1
		return .Failure
	case .Action:
		if node.callback != nil {
			s := node.callback(node, ctx)
			if s == .Success && fired != nil {fired^ = node.name}
			return s
		}
		return .Failure
	}
	return .Failure
}

Behavior :: struct {
	tree:     ^BTNode,
	ctx_data: rawptr,
	fired:    string,
	prepare:  proc(ctx: rawptr), // optional game hook called before each tick
	manual:   bool, // when true, the consumer drives ticks itself
}

BehaviorTreePlugin :: proc(app: ^App) {
	init_system_set(app, "update", "behavior", before("default"))
	add_system(app, "behavior", behavior_tick)
}

behavior_tick :: proc(world: ^World) {
	behaviors := slice(world, Behavior)
	for i in 0 ..< len(behaviors) {
		b := &behaviors[i]
		if b.manual || b.tree == nil {continue}
		if b.prepare != nil {b.prepare(b.ctx_data)}
		b.fired = ""
		bt_tick(b.tree, b.ctx_data, &b.fired)
	}
}
