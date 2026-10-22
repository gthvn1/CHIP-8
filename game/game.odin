package game

import "core:fmt"

State :: struct {
	counter: int,
}

@(export)
init :: proc() -> (rawptr, bool) {
	s, err := new(State)
	if err != .None {
		fmt.eprintln(err)
		return nil, false
	}
	return s, true
}

@(export)
deinit :: proc(ptr: rawptr) {
	free(ptr)
}

@(export)
display :: proc(state: rawptr) {
	s := cast(^State)state
	s.counter += 1
	fmt.printfln("Counter: %d", s.counter)
}
