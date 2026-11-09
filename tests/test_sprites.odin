package tests

// tests for the sprite cache. run with:
//
//	odin test tests -collection:raylib=<odin vendor raylib path>
//
// note: there is no full round-trip test here, on purpose. LoadTexture needs
// a GL context, and on macOS InitWindow must run on the main thread — but
// the test runner executes tests on spawned threads, so creating a window
// inside a test traps (SIGTRAP from AppKit). the cache round trip is
// verified against a real binary instead; what runs here is what survives
// without a window

import "core:testing"
import rl "vendor:raylib"
import ecs "../src"

// the sprite() constructor must give the defaults draw_sprite documents:
// natural size, no color change, full texture — so a bare ecs.sprite(tex)
// draws unshrunk and untinted with no extra setup
@(test)
sprite_constructor_uses_natural_defaults :: proc(t: ^testing.T) {
	s := ecs.sprite(rl.Texture2D{})
	testing.expect(t, s.scale == rl.Vector2{1, 1}, "scale defaults to 1")
	testing.expect(t, s.tint == rl.WHITE, "tint defaults to WHITE")
	testing.expect(t, s.source == rl.Rectangle{}, "source defaults to whole texture")

	// explicit values still win over the defaults
	s = ecs.sprite(rl.Texture2D{}, scale = {0.5, 2}, tint = rl.PURPLE)
	testing.expect(t, s.scale == rl.Vector2{0.5, 2}, "explicit scale respected")
	testing.expect(t, s.tint == rl.PURPLE, "explicit tint respected")
}

@(test)
unload_textures_on_empty_cache_is_a_noop :: proc(t: ^testing.T) {
	// no window, no loads — the destroy-time system must not crash on an
	// empty cache (nothing was ever loaded in this process's map)
	ecs.unload_textures()
	testing.expect(t, len(ecs.textures) == 0, "cache is empty after unload")
}
