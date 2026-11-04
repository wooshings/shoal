package main

import ecs "../src"

main :: proc() {
	app: ecs.App

	ecs.add_system(&app, "startup", start_audio)
}

start_audio :: proc() {
	ecs.play_sound("../assets/komm_susser_tod.mp3")
}
