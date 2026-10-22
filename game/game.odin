package game

import "core:fmt"

State :: struct {
	// The size of the struct *MUST* stay first. It is used by on_reload to
	// know if the struct has changed (it doesn't detect new order, only add/del fields)
	size:    int,
	counter: int,
}

// Using a default value for counter is just for debugging purpose, on_reload use a different
// one.
new_state :: proc(counter := 3) -> rawptr {
	s, err := new(State)
	if err != .None {
		fmt.eprintln(err)
		return nil
	}

	s.size = size_of(State)
	s.counter = counter
	return s
}

@(export)
init :: proc() -> rawptr {
	return new_state()
}

@(export)
deinit :: proc(ptr: rawptr) {
	free(ptr)
}

@(export)
on_reload :: proc(state: rawptr) -> rawptr {
	s := cast(^State)state
	if s.size != size_of(State) {
		// The struct has been modified. We need to return a new pointer.
		// The old one will be freed by the caller.
		return new_state(counter = 42)
	}

	return state
}

@(export)
display :: proc(state: rawptr) {
	s := cast(^State)state
	s.counter += 1
	fmt.printfln("Counter: %d", s.counter)
}
