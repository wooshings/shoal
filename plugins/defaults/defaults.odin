package defaults

import ecs "../../src"
import ui "../ui"

Batteries :: proc(app: ^ecs.App) {
	ecs.DefaultPlugin(app)
	ui.UIPlugin(app)
}
