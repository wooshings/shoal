package defaults

// batteries-included composition for shoal. this is a meta-plugin: it does
// not implement anything itself, it just composes DefaultPlugin with a curated
// set of community plugins so a project gets them in one line:
//
//	ecs.add_plugin(&app, defaults.Batteries)
//
// lean projects that want only the core keep using ecs.DefaultPlugin directly.
//
// adding a community plugin to the bundle is a one-line change here plus an
// import above — no rewrite of the plugin, no change to src/, no circular
// import (plugins may depend on src/, never the other way around).

import ecs "../../src"
import ui "../ui"

// core + the community plugins we consider "default". keep this list short and
// conservative: only plugins that are broadly useful and have no heavy deps.
Batteries :: proc(app: ^ecs.App) {
	ecs.DefaultPlugin(app)
	ui.UIPlugin(app)
}

