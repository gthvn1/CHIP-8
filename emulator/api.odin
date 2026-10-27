package emulator

import "core:fmt"

// dynamically linked, vendor:raylib uses system:raylib
// See $(odin root)/vendor/raylib/raylib.odin:102
import rl "vendor:raylib"

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
	return new_state()
}

@(export)
update :: proc(state: rawptr) {
	s := cast(^State)state

	if rl.IsKeyPressed(.R) {
		clear_state(s)
	}

	if rl.IsKeyPressed(.SPACE) {
		bin_insn := fetch(&s.chip)
		insn := decode(bin_insn)
		execute(&insn, &s.chip)
	}
}

@(export)
render :: proc(state: rawptr) {
	s := cast(^State)state
	chip := s.chip

	//  0          320                      960         1280
	//  ┌───────────┬────────────────────────┬───────────┐ 0
	//  │           │                        │           │
	//  │  Code     │   Screen 64*32 (×10)   │  State    │
	//  │  (desas.) │     640*320            │  V0..VF   │
	//  │           │                        │  I, PC    │
	//  │  320*720  ├────────────────────────┤  SP, pile │ 320
	//  │           │                        │  timers   │
	//  │           │   Debug/journal        │           │
	//  │           │     640*400            │  320*720  │
	//  │           │                        │           │
	//  └───────────┴────────────────────────┴───────────┘ 720

	screen_width := rl.GetScreenWidth()
	screen_height := rl.GetScreenHeight()

	rl.ClearBackground(rl.BLACK)

	render_code(
		rl.Rectangle{x = 0, y = 0, width = CODE_WIDTH, height = cast(f32)screen_height},
		&chip,
	)

	render_screen(
		rl.Rectangle {
			x = CODE_WIDTH,
			y = 0,
			width = CHIP8_WIDTH * SCALE,
			height = CHIP8_HEIGHT * SCALE,
		},
	)

	render_debug(
		rl.Rectangle {
			x = CODE_WIDTH,
			y = CHIP8_HEIGHT * SCALE,
			width = CHIP8_WIDTH * SCALE,
			height = cast(f32)(screen_height - CHIP8_HEIGHT * SCALE),
		},
		&chip,
	)

	render_state(
		rl.Rectangle {
			x = CODE_WIDTH + CHIP8_WIDTH * SCALE,
			y = 0,
			width = cast(f32)screen_width - (CODE_WIDTH + CHIP8_WIDTH * SCALE),
			height = cast(f32)screen_height,
		},
		&chip,
	)

}
