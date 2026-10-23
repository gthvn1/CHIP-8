package emulator

import "core:fmt"

// dynamically linked, vendor:raylib uses system:raylib
// See $(odin root)/vendor/raylib/raylib.odin:102
import rl "vendor:raylib"

MAGIC :: 0xDECAFBAD

State :: struct {
	// The magic and the size of the struct *MUST* stay first. It is used by on_reload to
	// know if the struct has changed (it doesn't detect new order, only add/del fields)
	magic:   int,
	size:    int,
	counter: int,
}

// Using a default value for counter is just for debugging purpose.
clear_state :: proc(state: ^State, counter := 0) {
	state^ = State {
		magic   = MAGIC,
		size    = size_of(State),
		counter = counter,
	}
}

new_state :: proc(counter := 3) -> rawptr {
	s, err := new(State)
	if err != .None {
		fmt.eprintln(err)
		return nil
	}

	clear_state(s, counter)
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

	if s.magic != MAGIC {
		fmt.eprintfln("Bad magic: expected %x got %x", MAGIC, s.magic)
		return nil
	}

	if s.size == size_of(State) {
		// Nothing to do (remember that we only detect new or removed fields).
		return state
	}

	// The struct has been modified. We need to return a new pointer.
	// The old one will be freed by the caller.
	return new_state(counter = 42)
}

@(export)
update :: proc(state: rawptr) {
	s := cast(^State)state

	if rl.IsKeyPressed(.R) {
		clear_state(s)
	} else {
		s.counter += 1
	}
}

@(export)
render :: proc(state: rawptr) {
	s := cast(^State)state

	text := fmt.caprintf("Counter: %05d", s.counter)
	defer delete(text)

	rl.ClearBackground(rl.BLACK)
	rl.DrawText(text, 200, 200, 20, rl.ORANGE)
}
