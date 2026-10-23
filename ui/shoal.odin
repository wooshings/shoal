package ui

import ml "vendor:microui"

ui_ctx: ^ml.Context

get_ctx :: proc() -> ^ml.Context {
	return ui_ctx
}
