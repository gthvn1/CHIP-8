package emulator

import "core:fmt"
import "core:os"

// dynamically linked, vendor:raylib uses system:raylib
// See $(odin root)/vendor/raylib/raylib.odin:102
import rl "vendor:raylib"

MAGIC :: 0xDECAFBAD

CHIP8_WIDTH :: 64
CHIP8_HEIGHT :: 32
SCALE :: 10

CODE_WIDTH :: 320

PROGRAM_START :: 0x200


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
		pc    = PROGRAM_START,
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

	copied := copy(state.memory[PROGRAM_START:], roms)
	if copied < len(roms) {
		fmt.eprintfln(
			"Out of memory: roms size %d bytes while our memory is %d byte",
			len(roms),
			len(state.memory[PROGRAM_START:]),
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

render_code :: proc(panel: rl.Rectangle, state: ^State) {
	pen := begin_panel(panel, rl.GREEN, title = "Code")

	// Let's print 50 line
	for idx := PROGRAM_START; idx <= PROGRAM_START + 50; idx += 2 {
		key := fmt.caprintf("0x%03x", idx)
		val := fmt.caprintf("0x%02x%02x", state.memory[idx], state.memory[idx + 1])
		if int(state.pc) == idx {
			write_row(&pen, key, val, rl.WHITE)
		} else {
			write_row(&pen, key, val, rl.GREEN)

		}
		delete(val)
		delete(key)
	}
}

render_screen :: proc(panel: rl.Rectangle) {
	begin_panel(panel, rl.WHITE)
}

Opcode :: enum {
	Unknown, // 0
	Clear,
	Return,
	Jump,
	Call,
	Seq,
	Sneq,
	Sveq,
	Set,
	Add,
}

Instruction :: struct {
	raw:    u16,
	opcode: Opcode,
	nnn:    u16, // 12-bit address
	nn:     u8, // 8-bit constant
	n:      u8, // 4-bit constant
	x:      u8, // Register identifier
	y:      u8, // Register identifier
}

Rule :: struct {
	mask:   u16,
	value:  u16,
	opcode: Opcode,
}

DECODER_RULES :: [?]Rule {
	{0xFFFF, 0x00E0, .Clear}, // 00E0
	{0xFFFF, 0x00EE, .Return}, // 00EE
	{0xF000, 0x1000, .Jump}, // 1NNN
	{0xF000, 0x2000, .Call}, // 2NNN
	{0xF000, 0x3000, .Seq}, // 3XNN
	{0xF000, 0x4000, .Sneq}, // 4XNN
	{0xF00F, 0x5000, .Sveq}, // 5XY0
	{0xF000, 0x6000, .Set}, // 6XNN
	{0xF000, 0x7000, .Add}, // 7XNN
}

decode :: proc(hi: u8, low: u8) -> (insn: Instruction) {
	raw := u16(hi) << 8 | u16(low)

	insn = Instruction {
		raw = raw,
		nnn = raw & 0x0FFF,
		nn  = u8(raw & 0xFF),
		n   = u8(raw & 0xF),
		x   = u8(raw >> 8 & 0xF),
		y   = u8(raw >> 4 & 0xF),
	}

	for r in DECODER_RULES {
		if (raw & r.mask) == r.value {
			insn.opcode = r.opcode
			return
		}
	}

	// As .Unkown is the first value of the enum it is the default one.
	// If we are here then .Unkown is returned.
	return
}

disassemble :: proc(insn: ^Instruction, state: ^State, output: []u8) -> string {
	switch insn.opcode {
	case .Unknown:
		return fmt.bprintf(output, "UNKN")
	case .Clear:
		return fmt.bprintf(output, "CLR")
	case .Return:
		return fmt.bprintf(output, "RET")
	case .Jump:
		return fmt.bprintf(output, "JMP 0x%04x", insn.nnn)
	case .Call:
		return fmt.bprintf(output, "CALL 0x%04x", insn.nnn)
	case .Seq:
		return fmt.bprintf(output, "SEQ V[%d]0x%x, 0x%x", insn.x, state.v[insn.x], insn.nn)
	case .Sneq:
		return fmt.bprintf(output, "SNEQ V[%d]0x%x, 0x%x", insn.x, state.v[insn.x], insn.nn)
	case .Sveq:
		return fmt.bprintf(
			output,
			"SVEQ V[%d]0x%04x, V[%d]0x%04x",
			insn.x,
			state.v[insn.x],
			insn.y,
			state.v[insn.y],
		)
	case .Set:
		return fmt.bprintf(output, "SET V[%d]0x%x, 0x%x", insn.x, state.v[insn.x], insn.nn)
	case .Add:
		return fmt.bprintf(output, "ADD V[%d]0x%x, 0x%x", insn.x, state.v[insn.x], insn.nn)
	}

	return fmt.bprintf(output, "UNREACHABLE")
}

render_debug :: proc(panel: rl.Rectangle, state: ^State) {
	pen := begin_panel(panel, rl.RED, title = "Debug")

	insn := decode(state.memory[state.pc], state.memory[state.pc + 1])
	key := fmt.caprintf("0x%04x: ", insn.raw)
	buf: [32]u8
	// To ensure we have a null terminaed string we pass the buffer minus
	// the last byte.
	text := disassemble(&insn, state, buf[:len(buf) - 1])
	write_row(&pen, key, cstring(raw_data(text)), rl.RED)
	delete(key)
}

render_state :: proc(panel: rl.Rectangle, state: ^State) {
	pen := begin_panel(panel, rl.GRAY, title = "State")

	// Program counter & Stack counter & Address Register
	{
		pc := fmt.caprintf("0x%04x", state.pc)
		write_row(&pen, "PC", pc, rl.YELLOW)
		delete(pc)

		sp := fmt.caprintf("%d (max %d)", state.sp, len(state.stack))
		write_row(&pen, "SP", sp, rl.YELLOW)
		delete(sp)

		i := fmt.caprintf("0x%04x", state.i)
		write_row(&pen, "I", i, rl.YELLOW)
		delete(i)
	}

	// Timer
	blank_row(&pen)
	{
		delay_t := fmt.caprintf("%d", state.delay_timer)
		sound_t := fmt.caprintf("%d", state.sound_timer)
		write_row(&pen, "Delay", delay_t, rl.SKYBLUE)
		write_row(&pen, "Sound", sound_t, rl.SKYBLUE)
		delete(delay_t)
		delete(sound_t)
	}

	// Display data registers
	blank_row(&pen)
	for v, idx in state.v {
		key := fmt.caprintf("V%X", idx)
		val := fmt.caprintf("0x%02x", v)
		write_row(&pen, key, val, rl.ORANGE)
		delete(val)
		delete(key)
	}
}

@(export)
render :: proc(state: rawptr) {
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
		cast(^State)state,
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
		cast(^State)state,
	)

	render_state(
		rl.Rectangle {
			x = CODE_WIDTH + CHIP8_WIDTH * SCALE,
			y = 0,
			width = cast(f32)screen_width - (CODE_WIDTH + CHIP8_WIDTH * SCALE),
			height = cast(f32)screen_height,
		},
		cast(^State)state,
	)

}
