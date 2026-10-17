package shoal

import "core:fmt"
import rl "vendor:raylib"

Timer :: struct {
	lifetime: f32,
	signal:   string,
}

@(private)
timers: map[string]Timer

start_timer :: proc(time: f32, signal: string) -> int {
	new_timer: Timer
	new_timer.lifetime = time
	timers[signal] = new_timer
	return len(timers)
}

get_timer :: proc(signal: string) -> Timer {
	if timer, exists := timers[signal]; exists {
		return timers[signal]
	}
	return Timer{}
}

run_timers :: proc() {
	for i, &t in timers {
		t.lifetime -= rl.GetFrameTime()
		if t.lifetime <= 0 {
			timers[i] = Timer{}
			if t.signal != "" {
				write(t.signal)
			}
		}
	}
}
