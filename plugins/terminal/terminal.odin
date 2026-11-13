package terminal

// thin facade over shoal's terminal render module: keeps the `terminal.`
// namespace without a circular import, since the implementation lives in
// src/ (package shoal) and plugins may only depend on src/, never the other
// way around.
import ecs "../../src"

TermColor :: ecs.TermColor
Character :: ecs.Character
Terminal :: ecs.Terminal

TerminalPlugin :: ecs.TerminalPlugin
TerminalRenderPlugin :: ecs.TerminalRenderPlugin
TerminalRendererPlugin :: ecs.TerminalRendererPlugin
