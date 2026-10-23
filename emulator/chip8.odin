package emulator

import "core:fmt"

// dynamically linked, vendor:raylib uses system:raylib
// See $(odin root)/vendor/raylib/raylib.odin:102
import rl "vendor:raylib"

MAGIC :: 0xDECAFBAD

CHIP8_WIDTH :: 64
CHIP8_HEIGHT :: 32
SCALE :: 10

CODE_WIDTH :: 320

State :: struct {
	// The magic and the size of the struct *MUST* stay first. It is used by on_reload to
	// know if the struct has changed (it doesn't detect new order, only add/del fields)
	magic:    int,
	size:     int,
	// CHIP-8 specific
	memory:   [4096]u8,
	v:        [16]u8, // Data registers (8-bits)
	i:        u16, // Address register (16-bits), 12 bits really used
	timer:    [2]u8, // two programmable timers (8-bits)
	keypad:   [16]u8, // TODO: it is 4bits so do we keep it u8
	graphics: [CHIP8_WIDTH * CHIP8_HEIGHT]u8, // TODO: 1 pixel is 1 bit so do we keep u8
	stack:    [64]u8, // Original allocation was 48
	pc:       int, // Program counter
}

// Using a default value for counter is just for debugging purpose.
clear_state :: proc(state: ^State, counter := 0) {
	state^ = State {
		magic = MAGIC,
		size  = size_of(State),
		pc    = 0x200,
		// All other fields are set to 0
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
	}
}

Pen :: struct {
	x_key:       i32,
	x_val:       i32,
	key_padding: i32,
	y:           i32,
	font_size:   i32,
	line_h:      i32,
}

write_row :: proc(pen: ^Pen, key: cstring, val: cstring, color: rl.Color) {
	rl.DrawText(key, pen.x_key, pen.y, pen.font_size, color)
	rl.DrawText(val, pen.x_val, pen.y, pen.font_size, color)
	pen.y += pen.line_h
}

blank_row :: proc(pen: ^Pen) {
	pen.y += pen.line_h
}

// Position the pen at the upper left corner of rect with a small margin
set_pen :: proc(pen: ^Pen, rect: rl.Rectangle, margin := 5) {
	m := cast(i32)margin
	pen^ = Pen {
		x_key     = cast(i32)rect.x + m,
		x_val     = cast(i32)rect.x + pen.key_padding + m,
		y         = cast(i32)rect.y + m,
		font_size = pen.font_size,
		line_h    = pen.line_h,
	}
}

@(export)
render :: proc(state: rawptr) {
	rl.ClearBackground(rl.BLACK)

	//  0          320                      960         1280
	//  ┌───────────┬────────────────────────┬───────────┐ 0
	//  │           │                        │           │
	//  │  Code     │   Screen 64*32 (×10)   │  Machin   │
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

	code_panel := rl.Rectangle {
		x      = 0,
		y      = 0,
		width  = CODE_WIDTH,
		height = cast(f32)screen_height,
	}

	screen_panel := rl.Rectangle {
		x      = CODE_WIDTH,
		y      = 0,
		width  = CHIP8_WIDTH * SCALE,
		height = CHIP8_HEIGHT * SCALE,
	}

	debug_panel := rl.Rectangle {
		x      = CODE_WIDTH,
		y      = CHIP8_HEIGHT * SCALE,
		width  = CHIP8_WIDTH * SCALE,
		height = cast(f32)(screen_height - CHIP8_HEIGHT * SCALE),
	}

	emu_state_panel := rl.Rectangle {
		x      = CODE_WIDTH + CHIP8_WIDTH * SCALE,
		y      = 0,
		width  = cast(f32)screen_width - (CODE_WIDTH + CHIP8_WIDTH * SCALE),
		height = cast(f32)screen_height,
	}

	rl.DrawRectangleLinesEx(code_panel, 2, rl.GRAY)
	rl.DrawRectangleLinesEx(screen_panel, 2, rl.GRAY)
	rl.DrawRectangleLinesEx(debug_panel, 2, rl.GRAY)
	rl.DrawRectangleLinesEx(emu_state_panel, 2, rl.GRAY)

	// Init a pen of size 20
	pen := Pen {
		key_padding = 130,
		font_size   = 20,
		line_h      = 25,
	}

	// Get state
	s := cast(^State)state

	set_pen(&pen, emu_state_panel, 20)

	// Program counter
	{
		val := fmt.caprintf("0x%04x", s.pc)
		write_row(&pen, "PC", val, rl.YELLOW)
		delete(val)
	}

	// Address register
	{
		blank_row(&pen)
		val := fmt.caprintf("0x%04x", s.i)
		write_row(&pen, "I", val, rl.BLUE)
		delete(val)
	}

	// Timer
	blank_row(&pen)
	for t, idx in s.timer {
		key := fmt.caprintf("Timer%d", idx)
		val := fmt.caprintf("0x%02x", t)
		write_row(&pen, key, val, rl.ORANGE)
		delete(val)
		delete(key)
	}

	// Display data registers
	blank_row(&pen)
	for v, idx in s.v {
		key := fmt.caprintf("V%X", idx)
		val := fmt.caprintf("0x%02x", v)
		write_row(&pen, key, val, rl.ORANGE)
		delete(val)
		delete(key)
	}
}
