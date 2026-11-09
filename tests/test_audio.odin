package tests

// tests for the audio plugin. run with:
//
//	odin test tests -collection:raylib=<odin vendor raylib path>
//
// the runner executes tests on multiple threads by default; the wiring test
// is stateless, and the lifecycle test is the sole owner of the package-global
// stream cache and the audio device

import ecs "../src"
import "core:math"
import "core:os"
import "core:testing"
import "core:time"
import rl "vendor:raylib"

@(test)
default_plugin_wires_audio :: proc(t: ^testing.T) {
	app: ecs.App
	ecs.DefaultPlugin(&app)
	// DefaultPlugin queues AudioPlugin via add_plugin; run() executes queued
	// plugins before startup — do that here so audio's systems register too
	ecs.AudioPlugin(&app)
	// audio's device init and the plugin's window init each live in their own
	// set anchored ahead of "default" in the startup walk: main()'s
	// registrations land in "default" before plugins run, so user startup
	// systems that play sound or need the GPU must run after both are open
	order := ecs.get_schedule_set_order(&app, "startup")
	testing.expect(t, len(order) == 2 && order[0] == "audio_init" && order[1] == "window", "plugin-owned sets run before default at startup")
	testing.expect(t, len(ecs.get_system(&app, "startup", "audio_init")) == 1, "audio device init in audio_init")
	testing.expect(t, len(ecs.get_system(&app, "startup", "window")) == 1, "window init in window set")
	testing.expect(t, len(ecs.get_system(&app, "startup", "default")) == 0, "startup default holds no plugin systems")
	testing.expect(t, len(ecs.get_system(&app, "update", "default")) == 3, "timers + cursor + stream pump")
	testing.expect(t, len(ecs.get_system(&app, "destroy", "default")) == 3, "texture unload + CloseWindow + audio shutdown")
	// the rest of the pipeline is untouched
	testing.expect(t, len(ecs.get_system(&app, "update", "post_update")) == 1, "signal clear still in place")
	testing.expect(t, len(ecs.get_schedule_set_order(&app, "draw")) == 3, "pre_draw/default/post_draw")
}

// generate a tiny 16-bit mono PCM wav: a 440 Hz sine, `seconds` long
@(private)
write_sine_wav :: proc(path: string, sample_rate: int, seconds: f32) -> bool {
	n := int(f32(sample_rate) * seconds)
	data_size := n * 2

	buf: [dynamic]u8
	// this odin has no postfix call-site spread, and strings don't spread
	// into byte variadics — append the chunk tags byte by byte
	tag :: proc(buf: ^[dynamic]u8, s: string) {
		for c in s {
			append(buf, u8(c))
		}
	}
	le16 :: proc(buf: ^[dynamic]u8, v: u16) {
		append(buf, u8(v & 0xFF), u8((v >> 8) & 0xFF))
	}
	le32 :: proc(buf: ^[dynamic]u8, v: u32) {
		append(buf, u8(v & 0xFF), u8((v >> 8) & 0xFF), u8((v >> 16) & 0xFF), u8((v >> 24) & 0xFF))
	}

	tag(&buf, "RIFF")
	le32(&buf, u32(36 + data_size))
	tag(&buf, "WAVE")
	tag(&buf, "fmt ")
	le32(&buf, 16)            // fmt chunk size
	le16(&buf, 1)             // PCM
	le16(&buf, 1)             // mono
	le32(&buf, u32(sample_rate))
	le32(&buf, u32(sample_rate * 2)) // byte rate
	le16(&buf, 2)             // block align
	le16(&buf, 16)            // bits per sample
	tag(&buf, "data")
	for i := 0; i < n; i += 1 {
		t := f32(i) / f32(sample_rate)
		sample := f32(math.sin(2 * math.PI * 440 * t)) * 0.5 * 32767
		le16(&buf, u16(i16(sample)))
	}

	f, err := os.create(path)
	if err != nil {
		return false
	}
	os.write(f, buf[:])
	os.close(f)
	return true
}

// the stateful test: sole owner of the stream cache and the device. first the
// no-device phase (every public proc must no-op cleanly), then a real round
// trip against the actual audio device — silent, master volume 0
@(test)
audio_lifecycle :: proc(t: ^testing.T) {
	// --- no device yet: play calls must not touch disk, control procs must
	// not crash on paths that were never loaded ---
	ecs.play_sound(".never_loaded.wav")
	ecs.set_volume(".never_loaded.wav", 0.5)
	ecs.stop(".never_loaded.ogg")
	ecs.pause(".never_loaded.ogg")
	ecs.resume(".never_loaded.ogg")
	ecs.master_volume(0.5)
	testing.expect(t, len(ecs.streams) == 0, "nothing cached without a device")

	// --- real device round trip ---
	ecs.startup()
	if !rl.IsAudioDeviceReady() {
		return // headless box: nothing further to integration-test
	}
	defer ecs.shutdown()
	ecs.master_volume(0.0) // the test must be silent

	path := ".test_sine.wav"
	if !write_sine_wav(path, 8000, 0.1) {
		testing.expectf(t, false, "could not write test wav")
		return
	}
	defer os.remove(path)

	// first call loads and caches, second replays the same asset
	ecs.play_sound(path)
	m, ok := ecs.streams[path]
	testing.expect(t, ok, "stream cached by path")
	testing.expect(t, rl.IsMusicStreamPlaying(m), "playing after play_sound")
	ecs.play_sound(path)
	testing.expect(t, len(ecs.streams) == 1, "replay hits the cache, no reload")
	ecs.pump_streams()
	testing.expect(t, rl.IsMusicStreamPlaying(m), "still playing after one pump")
	ecs.stop(path)
	testing.expect(t, !rl.IsMusicStreamPlaying(m), "stopped by stop")

	// pause / resume
	ecs.play_sound(path)
	ecs.pause(path)
	testing.expect(t, !rl.IsMusicStreamPlaying(m), "paused")
	ecs.resume(path)
	testing.expect(t, rl.IsMusicStreamPlaying(m), "resumed")
	ecs.stop(path)

	// a finished non-looping stream ends on its own: pump at frame pace until
	// the 0.1s track runs out, then the pump must leave it alone
	ecs.play_sound(path, false)
	finished := false
	for i := 0; i < 120; i += 1 {
		ecs.pump_streams()
		if !rl.IsMusicStreamPlaying(m) {
			finished = true
			break
		}
		time.sleep(16 * time.Millisecond)
	}
	testing.expect(t, finished, "non-looping stream reports not playing after its length ran out")

	// a looping stream survives past its length (0.1s track, ~20 frames)
	ecs.play_sound(path, true)
	for i := 0; i < 20; i += 1 {
		ecs.pump_streams()
		time.sleep(16 * time.Millisecond)
	}
	testing.expect(t, rl.IsMusicStreamPlaying(m), "looping stream still playing past its length")
	ecs.stop(path)

	// volume lands on the loaded asset without crashing
	ecs.set_volume(path, 0.5)

	// the deferred ecs.shutdown() unloads the cache and closes the device
}
