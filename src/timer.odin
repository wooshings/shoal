package shoal

import "core:fmt"
import rl "vendor:raylib"

// a named countdown: how many seconds are left (lifetime) and the name it
// fires under (also the key it's stored under)
Timer :: struct {
	lifetime: f32,
	signal:   string,
}

// queued when a timer runs out, for systems to pick up with
// read(TimerFired). run_timers below has the current caveat
TimerFired :: struct {
	name: string,
}

// timers stay in a package global for now, deliberately outside the
// World: they're keyed by name, not owned by an entity, so there's nothing
// per-world to hang them on yet. same goes for the signal buses in their
// own file
@(private)
timers: map[string]Timer

// start (or restart) a timer under this name. a name that's already running
// gets overwritten. it starts ticking on the next UPDATE, where run_timers
// counts it down
start_timer :: proc(time: f32, signal: string) {
	new_timer := Timer {
		lifetime = time,
		signal   = signal,
	}
	timers[signal] = new_timer
}

// remove the timer stored under this name entirely, freeing its map entry.
// safe to call for a name that isn't running (no-op). this is for releasing
// timers you created, not for reading them out -- use get_timer for that
stop_timer :: proc(signal: string) {
	delete_key(&timers, signal)
}

// the timer stored under this name, or a zero Timer if there is none. an
// expired timer is reset to Timer{} too, so lifetime != 0 means "still
// ticking" and lifetime <= 0 means "done (or never started)"
get_timer :: proc(signal: string) -> Timer {
	if timer, exists := timers[signal]; exists {
		return timers[signal]
	}
	return Timer{}
}

// registered at UPDATE by DefaultPlugin: ticks every timer down by the frame
// time, and when the remaining lifetime drops to roughly one frame's delta it
// resets its entry to Timer{} so get_timer reads it back zeroed. it compares
// against a fresh GetFrameTime() call, so it can reset a frame or two
// early. it's meant to then queue TimerFired{name = <timer name>} for
// read(TimerFired). like any signal, it's readable only until signal_system
// clears the buses at POST_UPDATE, see signals.odin for how that lands per
// schedule.
// known bug: the reset writes the same map slot t points at, so t.signal is
// already "" when it's checked just after and nothing gets queued, so
// TimerFired doesn't actually fire yet (the timers themselves work fine)
run_timers :: proc() {
	for i, &t in timers {
		t.lifetime -= rl.GetFrameTime()
		if t.lifetime <= rl.GetFrameTime() {
			timers[i] = Timer{}
			if t.signal != "" {
				write(TimerFired{name = t.signal})
			}
		}
	}
}
