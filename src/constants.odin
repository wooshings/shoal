package shoal

// schedule ids for add_system. run() walks them in this order:
//
//	STARTUP      once, before the first frame (plugins run before this)
//	PRE_UPDATE   \
//	UPDATE        | every frame, before any drawing
//	POST_UPDATE  /   (signal_system clears the buses here)
//	PRE_DRAW     \
//	DRAW          | every frame, the raylib drawing part
//	LATE_DRAW    /   (LATE_DRAW runs after every DRAW system, for overlays)
//	POST_DRAW    once per frame, after all drawing
//	DESTROY      once, after the loop exits and the window closes
//
// DefaultPlugin opens the raylib frame at PRE_DRAW (BeginDrawing + clear) and
// closes it at POST_DRAW (EndDrawing), so DRAW is where your draw calls go.
// renderers that flush accumulated draw state (like the ui plugin replaying
// microui's command list) go on LATE_DRAW, so they run after all game DRAW
// systems but still inside the raylib frame.
STARTUP :: 0
PRE_UPDATE :: 1
UPDATE :: 2
POST_UPDATE :: 3
PRE_DRAW :: 4
DRAW :: 5
LATE_DRAW :: 6
POST_DRAW :: 7
DESTROY :: 8
