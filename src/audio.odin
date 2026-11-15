package shoal

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

AudioPlugin :: proc(app: ^App) {

	init_system_set(app, "startup", "audio_init", before("default"))
	add_system(app, "audio_init", startup)
	add_system(app, "update", pump_streams)
	add_system(app, "destroy", shutdown)
}

streams: map[string]rl.Music

startup :: proc() {
	rl.InitAudioDevice()
}

pump_streams :: proc() {
	for _, m in streams {
		if rl.IsMusicStreamPlaying(m) {
			rl.UpdateMusicStream(m)
		}
	}
}

shutdown :: proc() {
	for _, m in streams {
		rl.StopMusicStream(m)
		rl.UnloadMusicStream(m)
	}
	delete(streams)
	rl.CloseAudioDevice()
}

play_sound :: proc(path: string, loop := false) {
	if !rl.IsAudioDeviceReady() {
		return
	}
	m, ok := streams[path]
	if !ok {
		m = rl.LoadMusicStream(strings.clone_to_cstring(path))

		if m.ctxType == 0 {
			panic(fmt.tprintf("play_sound: could not load audio %q", path))
		}
		streams[path] = m
	}
	m.looping = loop
	rl.PlayMusicStream(m)
	streams[path] = m
}

stop :: proc(path: string) {
	if m, ok := streams[path]; ok {
		rl.StopMusicStream(m)
	}
}

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

set_volume :: proc(path: string, volume: f32) {
	if m, ok := streams[path]; ok {
		rl.SetMusicVolume(m, volume)
	}
}

master_volume :: proc(volume: f32) {
	rl.SetMasterVolume(volume)
}
