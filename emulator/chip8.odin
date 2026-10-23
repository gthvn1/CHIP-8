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
	magic:       int,
	size:        int,
	// CHIP-8 specific
	memory:      [4096]u8,
	v:           [16]u8, // Data registers (8-bits)
	i:           u16, // Address register (16-bits), 12 bits really used
	delay_timer: u8,
	sound_timer: u8,
	keypad:      [16]bool, // accept input from a 16-key keypad, true is pressed, false otherwise
	graphics:    [CHIP8_WIDTH * CHIP8_HEIGHT]bool, // a pixel is on or off
	stack:       [16]u16, // Used for address (12-bits) so use u16. We need to store at least 12 addr.
	pc:          u16, // Program counter (store addresses)
	sp:          uint, // Stack pointer, an index in the stack
}

clear_state :: proc(state: ^State) {
	state^ = State {
		magic = MAGIC,
		size  = size_of(State),
		pc    = 0x200,
		// All other fields are set to 0
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
}

Pen :: struct {
	x_key:     i32,
	x_val:     i32,
	y:         i32,
	font_size: i32,
	line_h:    i32,
}

write_row :: proc(pen: ^Pen, key: cstring, val: cstring, color: rl.Color) {
	rl.DrawText(key, pen.x_key, pen.y, pen.font_size, color)
	rl.DrawText(val, pen.x_val, pen.y, pen.font_size, color)
	pen.y += pen.line_h
}

blank_row :: proc(pen: ^Pen) {
	pen.y += pen.line_h
}

begin_panel :: proc(
	panel: rl.Rectangle,
	color: rl.Color,
	thick: f32 = 2,
	margin: i32 = 5,
	key_padding: i32 = 100,
	font_size: i32 = 20,
	line_h: i32 = 26,
	title: cstring = nil,
) -> Pen {
	// y=0   ┌─────────────────────┐
	// y=5   │  Title              │  <- title : 20 px
	// y=25  │─────────────────────│  <- line under the title
	// y=30  │  PC     0x0200      │  <- pen starts here + margin
	// y=56  │  I      0x0000      │
	//       │  ...                │
	//       └─────────────────────┘
	line_pos: i32 = 0 // If there is no title

	p_w := cast(i32)panel.width
	p_x := cast(i32)panel.x
	p_y := cast(i32)panel.y

	rl.DrawRectangleLinesEx(panel, thick, color)

	if title != nil {
		line_pos = font_size + margin
		title_space := (p_w - rl.MeasureText(title, font_size)) / 2
		rl.DrawText(title, p_x + title_space, p_y + margin, font_size, color)
		rl.DrawLine(p_x, p_y + line_pos, p_w + p_x, p_y + line_pos, color)
	}

	return Pen {
		x_key = p_x + margin,
		x_val = p_x + key_padding + margin,
		y = p_y + line_pos + margin,
		font_size = font_size,
		line_h = line_h,
	}
}

@(export)
render :: proc(state: rawptr) {
	s := cast(^State)state

	rl.ClearBackground(rl.BLACK)

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

	// Draw Code
	begin_panel(code_panel, rl.GREEN, title = "Code")
	begin_panel(screen_panel, rl.WHITE)
	begin_panel(debug_panel, rl.RED, title = "Debug")

	// Draw Machine state
	pen := begin_panel(emu_state_panel, rl.GRAY, title = "State")

	// Program counter & Stack counter & Address Register
	{
		pc := fmt.caprintf("0x%04x", s.pc)
		write_row(&pen, "PC", pc, rl.YELLOW)
		delete(pc)

		sp := fmt.caprintf("%d (max %d)", s.sp, len(s.stack))
		write_row(&pen, "SP", sp, rl.YELLOW)
		delete(sp)

		i := fmt.caprintf("0x%04x", s.i)
		write_row(&pen, "I", i, rl.YELLOW)
		delete(i)
	}

	// Timer
	blank_row(&pen)
	{
		delay_t := fmt.caprintf("%d", s.delay_timer)
		sound_t := fmt.caprintf("%d", s.sound_timer)
		write_row(&pen, "Delay", delay_t, rl.SKYBLUE)
		write_row(&pen, "Sound", sound_t, rl.SKYBLUE)
		delete(delay_t)
		delete(sound_t)
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
