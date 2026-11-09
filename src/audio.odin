package shoal

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// wire audio into the app. opens the audio device before any user startup
// system runs (the "audio_init" set is anchored ahead of "default" in the
// "startup" walk), keeps audio streams fed at "update", unloads everything
// and closes the device at "destroy". add it like:
//
//	ecs.add_plugin(&app, ecs.AudioPlugin)
AudioPlugin :: proc(app: ^App) {
	// the device must be open before user startup systems play anything —
	// main()'s registrations land in "default" before plugins run, so anchor
	// ahead of it instead of relying on registration order
	init_system_set(app, "startup", "audio_init", before("default"))
	add_system(app, "audio_init", startup)
	add_system(app, "update", pump_streams)
	add_system(app, "destroy", shutdown)
}

// every sound is a music stream under the hood: raylib decodes incrementally
// from the compressed file (no fully-decoded PCM sitting in RAM) and the
// plugin's "update" system keeps each playing stream fed. assets are cached
// by path — the path IS the handle; first call loads from disk, every call
// after replays the loaded asset. public so callers can see what is loaded
// (and so the lifecycle test can assert cache hits)
streams: map[string]rl.Music

// open the audio device. registered into the "audio_init" set at startup;
// public so the lifecycle test can drive it without a full schedule walk
startup :: proc() {
	rl.InitAudioDevice()
}

// fill every playing stream's buffers once per frame. a stream nobody
// updates goes silent. public so the lifecycle test can pump by hand
pump_streams :: proc() {
	for _, m in streams {
		if rl.IsMusicStreamPlaying(m) {
			rl.UpdateMusicStream(m)
		}
	}
}

// stop and unload every cached stream, then close the device. public so the
// lifecycle test can drive it without a full schedule walk
shutdown :: proc() {
	for _, m in streams {
		rl.StopMusicStream(m)
		rl.UnloadMusicStream(m)
	}
	delete(streams)
	rl.CloseAudioDevice()
}

// play a sound or music file. loads it on first use, replays on every call —
// calling it again restarts from the top. loop makes it wrap at the end
// instead of stopping. does nothing if the audio device failed to open
// (headless builds)
//
//	audio.play_sound("sounds/explosion.wav")
//	audio.play_sound("sounds/theme.ogg", true)
play_sound :: proc(path: string, loop := false) {
	if !rl.IsAudioDeviceReady() {
		return
	}
	m, ok := streams[path]
	if !ok {
		m = rl.LoadMusicStream(strings.clone_to_cstring(path))
		// a failed load returns a zeroed Music (ctxType 0, nil buffer) and
		// PlayMusicStream on it is a silent no-op — a typo'd asset path would
		// just play nothing forever. panic instead, same fail-fast rule as
		// add_system against an undeclared schedule
		if m.ctxType == 0 {
			panic(fmt.tprintf("play_sound: could not load audio %q", path))
		}
		streams[path] = m
	}
	m.looping = loop
	rl.PlayMusicStream(m)
	streams[path] = m
}

// stop a stream. play starts it over from the top
stop :: proc(path: string) {
	if m, ok := streams[path]; ok {
		rl.StopMusicStream(m)
	}
}

// pause / resume a stream. resume is a no-op if it wasn't playing
pause :: proc(path: string) {
	if m, ok := streams[path]; ok {
		rl.PauseMusicStream(m)
	}
}

resume :: proc(path: string) {
	if m, ok := streams[path]; ok {
		rl.ResumeMusicStream(m)
	}
}

// set the volume for a path, 0.0 .. 1.0. the setting sticks to the loaded
// asset, so set it any time after the first play call — for a path that was
// never loaded this is a no-op
set_volume :: proc(path: string, volume: f32) {
	if m, ok := streams[path]; ok {
		rl.SetMusicVolume(m, volume)
	}
}

// master volume for everything going through the audio device
master_volume :: proc(volume: f32) {
	rl.SetMasterVolume(volume)
}
