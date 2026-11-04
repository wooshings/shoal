package shoal

import "core:strings"
import rl "vendor:raylib"

// a signal fired when audio starts playing, only on the transition from
// stopped/paused to playing, not every frame. see AudioFinished below for
// the matching end signal.
AudioStarted :: struct {
	entity:   Entity,
	is_music: bool,
}

// a signal fired when a sound or music stream finishes. fires after the
// playing state transitions to Stopped, and after the audio device is
// closed (headless builds might never fire this, see AudioDeviceError).
AudioFinished :: struct {
	entity:   Entity,
	is_music: bool,
}

// fires when InitAudioDevice fails, usually in headless builds or when no
// audio hardware is available. see startup_audio below.
AudioDeviceError :: struct {
	message: string,
}

// opaque handle for sounds and music loaded through the global API.
// backed by a pool index, see audio_pool and audio_count below.
AudioHandle :: u32

// load a sound from file and return a handle. the sound is cached by path
// so subsequent calls with the same path return the same handle without
// reloading from disk. you can control it with stop_sound, set_sound_volume,
// etc. see path_to_handle below for the cache.
//
//     handle := play_sound("sounds/explosion.wav")
//     stop_sound(handle)
play_sound :: proc(path: string) -> AudioHandle {
	// check path cache first, play it again if already loaded
	if cached, ok := path_to_handle[path]; ok {
		rl.PlaySound(audio_pool[int(cached)].sound)
		return cached
	}

	cpath := strings.clone_to_cstring(path)
	wave := rl.LoadWave(cpath)
	sound := rl.LoadSoundFromWave(wave)
	rl.UnloadWave(wave)

	handle := AudioHandle(audio_count)
	if int(handle) >= len(audio_pool) {
		append(&audio_pool, AudioEntry{})
	}
	audio_pool[int(handle)] = AudioEntry {
		sound    = sound,
		playing  = true,
		is_music = false,
		volume   = 1.0,
	}
	path_to_handle[path] = handle
	audio_count += 1
	return handle
}

// stop a playing sound by its handle. no-op if the handle is invalid or
// the sound was never loaded. see audio_pool and audio_count below.
stop_sound :: proc(handle: AudioHandle) {
	if int(handle) < audio_count {
		rl.StopSound(audio_pool[int(handle)].sound)
		audio_pool[int(handle)].playing = false
	}
}

// set volume for a specific sound handle, clamped to 0.0 .. 1.0.
// the value is also stored in the pool entry so it survives across calls.
// see audio_pool below.
set_sound_volume :: proc(handle: AudioHandle, volume: f32) {
	if int(handle) < audio_count {
		rl.SetSoundVolume(audio_pool[int(handle)].sound, volume)
		audio_pool[int(handle)].volume = volume
	}
}

// check if a sound is currently playing. returns false for invalid handles
// or sounds that were never loaded. see audio_pool below.
is_sound_playing :: proc(handle: AudioHandle) -> bool {
	if int(handle) < audio_count {
		return rl.IsSoundPlaying(audio_pool[int(handle)].sound)
	}
	return false
}

// load and start playing a music stream from file. returns a handle.
// music streams are for longer audio (background music, ambient loops)
// and are updated every frame by process_audio_components, see below.
// the sound is cached by path so subsequent calls with the same path
// return the same handle without reloading. see path_to_handle below.
//
//     handle := play_music("sounds/theme.ogg")
play_music :: proc(path: string) -> AudioHandle {
	// check path cache first, play it again if already loaded
	if cached, ok := path_to_handle[path]; ok {
		rl.PlayMusicStream(audio_pool[int(cached)].music)
		return cached
	}

	cpath := strings.clone_to_cstring(path)
	music := rl.LoadMusicStream(cpath)

	handle := AudioHandle(audio_count)
	if int(handle) >= len(audio_pool) {
		append(&audio_pool, AudioEntry{})
	}
	audio_pool[int(handle)] = AudioEntry {
		music    = music,
		playing  = true,
		is_music = true,
		volume   = 1.0,
	}
	path_to_handle[path] = handle
	audio_count += 1
	return handle
}

// stop the currently playing music by handle. no-op if the handle is
// invalid or the music was never loaded. see audio_pool below.
stop_music :: proc(handle: AudioHandle) {
	if int(handle) < audio_count {
		rl.StopMusicStream(audio_pool[int(handle)].music)
		audio_pool[int(handle)].playing = false
	}
}

// pause the currently playing music. no-op if the handle is invalid or
// not a music stream. see audio_pool below.
pause_music :: proc(handle: AudioHandle) {
	if int(handle) < audio_count && audio_pool[int(handle)].is_music {
		rl.PauseMusicStream(audio_pool[int(handle)].music)
	}
}

// resume paused music. no-op if the handle is invalid or not a music
// stream. see audio_pool below.
resume_music :: proc(handle: AudioHandle) {
	if int(handle) < audio_count && audio_pool[int(handle)].is_music {
		rl.ResumeMusicStream(audio_pool[int(handle)].music)
	}
}

// seek music to a position in seconds. no-op if the handle is invalid or
// not a music stream. see audio_pool below.
seek_music :: proc(handle: AudioHandle, position: f32) {
	if int(handle) < audio_count && audio_pool[int(handle)].is_music {
		rl.SeekMusicStream(audio_pool[int(handle)].music, position)
	}
}

// get current music playback position in seconds. returns 0.0 for invalid
// handles or non-music streams. see audio_pool below.
get_music_time_played :: proc(handle: AudioHandle) -> f32 {
	if int(handle) < audio_count && audio_pool[int(handle)].is_music {
		return rl.GetMusicTimePlayed(audio_pool[int(handle)].music)
	}
	return 0.0
}

// get total music length in seconds. returns 0.0 for invalid handles or
// non-music streams. see audio_pool below.
get_music_time_length :: proc(handle: AudioHandle) -> f32 {
	if int(handle) < audio_count && audio_pool[int(handle)].is_music {
		return rl.GetMusicTimeLength(audio_pool[int(handle)].music)
	}
	return 0.0
}

// set volume for a specific music handle, clamped to 0.0 .. 1.0.
// the value is also stored in the pool entry so it survives across calls.
// see audio_pool below.
set_music_volume :: proc(handle: AudioHandle, volume: f32) {
	if int(handle) < audio_count {
		rl.SetMusicVolume(audio_pool[int(handle)].music, volume)
		audio_pool[int(handle)].volume = volume
	}
}

// set/get the master volume for all audio (listener volume). this affects
// everything: sounds, music, everything that goes through raylib's audio
// device. see startup_audio below.
set_master_volume :: proc(volume: f32) {
	rl.SetMasterVolume(volume)
}

// global pool for sounds and music loaded through the global API.
// handles are 0-based indices into this array. see audio_count below.
@(private)
audio_pool: [dynamic]AudioEntry
@(private)
audio_count: int = 0

// path cache: reuse loaded sounds/music instead of reloading from disk.
// maps file path strings to handles, see play_sound and play_music above.
@(private)
path_to_handle: map[string]AudioHandle

// a single entry holding both an rl.Sound and an rl.Music, plus flags
// and metadata. raylib's types are small enough that one struct for
// both works fine. see audio_pool above.
AudioEntry :: struct {
	sound:    rl.Sound,
	music:    rl.Music,
	playing:  bool,
	is_music: bool,
	volume:   f32,
}

// audio plugin: initializes the audio device at STARTUP, processes Audio
// components at UPDATE, cleans up finished sounds at UPDATE, and frees
// everything at DESTROY. add it like: ecs.add_plugin(&app, AudioPlugin)
// see startup_audio, process_audio_components, cleanup_finished_sounds,
// and destroy_audio below.
AudioPlugin :: proc(app: ^App) {
	add_system(app, STARTUP, startup_audio)
	add_system(app, UPDATE, process_audio_components)
	add_system(app, UPDATE, cleanup_finished_sounds)
	add_system(app, DESTROY, destroy_audio)
}

// init the audio device. only called once at STARTUP by AudioPlugin.
// if this fails (headless builds, no audio hardware), systems that try
// to play audio will silently do nothing. see AudioDeviceError above.
@(private)
startup_audio :: proc(world: ^World) {
	rl.InitAudioDevice()
}

// close the audio device and unload all sounds/music from the pool.
// called once at DESTROY by AudioPlugin. see audio_pool and audio_count
// above.
@(private)
destroy_audio :: proc(world: ^World) {
	rl.CloseAudioDevice()
	for i := 0; i < audio_count; i += 1 {
		if audio_pool[i].is_music {
			rl.UnloadMusicStream(audio_pool[i].music)
		} else {
			rl.UnloadSound(audio_pool[i].sound)
		}
	}
	delete(audio_pool)
	delete(path_to_handle)
}

// process Audio components on entities: plays sounds, updates music
// streams, handles looping, and fires AudioStarted/AudioFinished signals.
// see Audio and AudioState in audio.odin for the component definition,
// and the signals above.
@(private)
process_audio_components :: proc(world: ^World) {
	components := slice(world, Audio)
	entities := slice_entity(world, Audio)

	for &v, i in components {
		entity := entities[i]

		switch v.state {
		case AudioState.Playing:
			// one-shot sound (frameCount == 0 means no sound loaded)
			if v.sound.frameCount != 0 {
				rl.PlaySound(v.sound)
				rl.SetSoundVolume(v.sound, v.volume)
				rl.SetSoundPitch(v.sound, v.pitch)
				rl.SetSoundPan(v.sound, v.pan)
				write(AudioStarted{entity = entity, is_music = false})

				// check if a very short sound already finished this frame
				if !rl.IsSoundPlaying(v.sound) {
					v.state = AudioState.Stopped
					write(AudioFinished{entity = entity, is_music = false})
				}
			} else if v.music.ctxType != 0 {
				// background music (ctxType == 0 means no music loaded)
				rl.PlayMusicStream(v.music)
				rl.SetMusicVolume(v.music, v.volume)
				rl.SetMusicPitch(v.music, v.pitch)
				rl.SetMusicPan(v.music, v.pan)
				write(AudioStarted{entity = entity, is_music = true})

				// update music stream buffers every frame
				rl.UpdateMusicStream(v.music)

				// loop handling: if looping and reached end, seek to start
				if v.looping && rl.GetMusicTimePlayed(v.music) >=
						rl.GetMusicTimeLength(v.music) {
					rl.SeekMusicStream(v.music, 0)
				}
			}

		case AudioState.Paused:
			// do nothing this frame (paused)

		case AudioState.Stopped:
			// nothing to do; component can be removed by a cleanup system

		case AudioState.None:
			// no-op
		}
	}
}

// unload sounds and music from the global pool that have been marked as
// not playing anymore. called every UPDATE by AudioPlugin, runs after
// process_audio_components so finished sounds from this frame get cleaned
// up before the next frame. see audio_pool and audio_count above.
@(private)
cleanup_finished_sounds :: proc() {
	for i := 0; i < audio_count; i += 1 {
		if !audio_pool[i].playing {
			if audio_pool[i].is_music {
				rl.UnloadMusicStream(audio_pool[i].music)
			} else {
				rl.UnloadSound(audio_pool[i].sound)
			}
			audio_pool[i] = AudioEntry{}
		}
	}
}
