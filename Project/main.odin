package Project

import "core:fmt"
import Engine "../Engine/src/core"

RUN_EDITOR :: #config(RUN_EDITOR, false)

main :: proc() {
	fmt.println("========================================")
	fmt.println(" PROJECT START")
	fmt.println("========================================")

	fmt.println("RUN_EDITOR: ", RUN_EDITOR)

	fmt.println("Calling Engine.init()...")

	init_ok := Engine.init(
		run_game,
		RUN_EDITOR,
	)

	fmt.println("Engine.init() returned: ", init_ok)

	if !init_ok {
		fmt.println("Engine initialization failed.")
		return
	}

	fmt.println("Calling Engine.run()...")

	Engine.run()

	fmt.println("Engine.run() returned.")

	fmt.println("Calling Engine.destroy()...")

	destroy_ok := Engine.destroy()

	fmt.println("Engine.destroy() returned: ", destroy_ok)

	if !destroy_ok {
		fmt.println("Failed to destroy engine properly.")
		return
	}

	fmt.println("========================================")
	fmt.println(" PROJECT EXIT")
	fmt.println("========================================")
}


run_game :: proc() {
	fmt.println("Running game...")
}