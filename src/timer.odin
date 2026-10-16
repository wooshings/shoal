package shoal

import "core:fmt"
import rl "vendor:raylib"

Timer :: struct {
	lifetime: f32,
	signal:   string,
}

@(private)
timers: [dynamic]Timer

start_timer :: proc(time: f32, signal: string = "") -> int {
	new_timer: Timer
	new_timer.lifetime = time
	append(&timers, new_timer)
	return len(timers)
}

get_timer :: proc(index: int) -> Timer {
	if index <= len(timers) - 1 {
		return timers[index]
	}
	return Timer{}
}

run_timers :: proc() {
	for &t, i in timers {
		t.lifetime -= rl.GetFrameTime()
		if t.lifetime <= 0 {
			unordered_remove(&timers, i)
			if t.signal != "" {
				write(t.signal)
			}
		}
	}
}
