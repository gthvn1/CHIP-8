package game

import "core:fmt"

@(export)
display :: proc(counter: ^int) {
	counter^ += 1
	fmt.printfln("Counter: %d", counter^)
}
