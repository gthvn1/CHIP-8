package emulator

import "core:fmt"
import "core:os"

// dynamically linked, vendor:raylib uses system:raylib
// See $(odin root)/vendor/raylib/raylib.odin:102
import rl "vendor:raylib"

MAGIC :: 0xDECAFBAD

State :: struct {
	// The magic and the size of the struct *MUST* stay first. It is used by on_reload to
	// know if the struct has changed (it doesn't detect new order, only add/del fields)
	magic: int,
	size:  int,
	// CHIP-8 specific
	chip:  Chip,
}

clear_state :: proc(state: ^State) {
	state^ = State {
		magic = MAGIC,
		size = size_of(State),
		chip = {pc = PROGRAM_START},
		// All other fields are set to 0
	}

	// TODO: get the ROMs from command line
	f, open_err := os.open("./roms/ibm-logo.ch8")
	if open_err != nil {
		fmt.eprintln(os.error_string(open_err))
		return
	}
	defer os.close(f)

	roms, read_err := os.read_entire_file_from_file(f, context.allocator)
	if read_err != nil {
		fmt.eprintln(os.error_string(read_err))
		return
	}
	defer delete(roms)

	copied := copy(state.chip.memory[PROGRAM_START:], roms)
	if copied < len(roms) {
		fmt.eprintfln(
			"Out of memory: roms size %d bytes while our memory is %d byte",
			len(roms),
			len(state.chip.memory[PROGRAM_START:]),
		)
		return
	}
}

new_state :: proc() -> rawptr {
	s, err := new(State)
	if err != .None {
		fmt.eprintln(err)
		return nil
	}

	clear_state(s)
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
	return new_state()
}

@(export)
update :: proc(state: rawptr) {
	s := cast(^State)state

	if rl.IsKeyPressed(.R) {
		clear_state(s)
	}

	if rl.IsKeyPressed(.SPACE) {
		opcode, ok := fetch(&s.chip)
		if !ok {
			fmt.eprintfln("Failed to fetch (PC=0x%04x)", s.chip.pc)
			return
		}
		insn := decode(opcode)
		execute(&insn, &s.chip)
	}
}

@(export)
render :: proc(state: rawptr) {
	s := cast(^State)state
	chip := &s.chip

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
		chip,
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
		chip,
	)

	render_state(
		rl.Rectangle {
			x = CODE_WIDTH + CHIP8_WIDTH * SCALE,
			y = 0,
			width = cast(f32)screen_width - (CODE_WIDTH + CHIP8_WIDTH * SCALE),
			height = cast(f32)screen_height,
		},
		chip,
	)

}
