package shoal

// schedule ids for add_system — run() walks them in this order:
//
//	STARTUP      once, before the first frame (plugins run before this)
//	PRE_UPDATE   \
//	UPDATE        | every frame, before any drawing
//	POST_UPDATE  /   (signal_system clears the buses here)
//	PRE_DRAW     \
//	DRAW          | every frame, the raylib drawing part
//	POST_DRAW    /
//	DESTROY      once, after the loop exits and the window closes
//
// DefaultPlugin opens the raylib frame at PRE_DRAW (BeginDrawing + clear) and
// closes it at POST_DRAW (EndDrawing), so DRAW is where your draw calls go.
STARTUP :: 0
PRE_UPDATE :: 1
UPDATE :: 2
POST_UPDATE :: 3
PRE_DRAW :: 4
DRAW :: 5
POST_DRAW :: 6
DESTROY :: 7

// easing ids for the (wip) Tween.ease field — see tween.odin, nothing reads
// them yet
EASE_IN :: 0
EASE_OUT :: 1
EASE_IN_OUT :: 2
