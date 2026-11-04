package shoal

// tests for the sprite cache. run with:
//
//	odin test src -collection:raylib=<odin vendor raylib path>
//
// note: there is no full round-trip test here, on purpose. LoadTexture needs
// a GL context, and on macOS InitWindow must run on the main thread — but
// the test runner executes tests on spawned threads, so creating a window
// inside a test traps (SIGTRAP from AppKit). the cache round trip is
// verified against a real binary instead; what runs here is what survives
// without a window

import "core:testing"

@(test)
unload_textures_on_empty_cache_is_a_noop :: proc(t: ^testing.T) {
	// no window, no loads — the destroy-time system must not crash on an
	// empty cache (nothing was ever loaded in this process's map)
	unload_textures()
	testing.expect(t, len(textures) == 0, "cache is empty after unload")
}
