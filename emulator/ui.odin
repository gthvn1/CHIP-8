package emulator

import "core:fmt"

// dynamically linked, vendor:raylib uses system:raylib
// See $(odin root)/vendor/raylib/raylib.odin:102
import rl "vendor:raylib"

SCALE :: 10

CODE_WIDTH :: 320

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

render_code :: proc(panel: rl.Rectangle, chip: ^Chip) {
	pen := begin_panel(panel, rl.GREEN, title = "Code")

	// Let's print 50 line
	for idx := PROGRAM_START; idx <= PROGRAM_START + 50; idx += 2 {
		key := fmt.caprintf("0x%03x", idx)
		val := fmt.caprintf("0x%02x%02x", chip.memory[idx], chip.memory[idx + 1])
		if int(chip.pc) == idx {
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

render_debug :: proc(panel: rl.Rectangle, state: ^State) {
	chip := &state.chip
	pen := begin_panel(panel, rl.WHITE, title = "Debug")

	// Print the history
	start := state.idx
	end := state.idx + len(state.traces)
	for idx in start ..< end {
		addr := fmt.caprintf("0x%03x", state.traces[idx % len(state.traces)].addr)
		text := cstring(raw_data(state.traces[idx % len(state.traces)].text[:]))
		write_row(&pen, addr, text, rl.GRAY)
		delete(addr)
	}

	// And print the current instruction, don't fetch here, just decode.
	opcode, ok := read_opcode(chip, chip.pc)
	if !ok {
		val := fmt.caprintf("Failed to fetch 0x%03x", chip.pc)
		write_row(&pen, val, "", rl.RED)
		delete(val)
	} else {
		insn := decode(opcode)

		key := fmt.caprintf("0x%03x", chip.pc)
		buf: [32]u8
		// To ensure we have a null terminaed string we pass the buffer minus
		// the last byte.
		text := disassemble(&insn, buf[:len(buf) - 1])
		write_row(&pen, key, cstring(raw_data(text)), rl.WHITE)
		delete(key)
	}
}

render_state :: proc(panel: rl.Rectangle, chip: ^Chip) {
	pen := begin_panel(panel, rl.GRAY, title = "State")

	// Program counter & Stack counter & Address Register
	{
		pc := fmt.caprintf("0x%03x", chip.pc)
		write_row(&pen, "PC", pc, rl.YELLOW)
		delete(pc)

		sp := fmt.caprintf("%d (max %d)", chip.sp, len(chip.stack))
		write_row(&pen, "SP", sp, rl.YELLOW)
		delete(sp)

		i := fmt.caprintf("0x%03x", chip.i)
		write_row(&pen, "I", i, rl.YELLOW)
		delete(i)
	}

	// Timer
	blank_row(&pen)
	{
		delay_t := fmt.caprintf("%d", chip.delay_timer)
		sound_t := fmt.caprintf("%d", chip.sound_timer)
		write_row(&pen, "Delay", delay_t, rl.SKYBLUE)
		write_row(&pen, "Sound", sound_t, rl.SKYBLUE)
		delete(delay_t)
		delete(sound_t)
	}

	// Display data registers
	blank_row(&pen)
	for v, idx in chip.v {
		key := fmt.caprintf("V%X", idx)
		val := fmt.caprintf("0x%02x", v)
		write_row(&pen, key, val, rl.ORANGE)
		delete(val)
		delete(key)
	}
}
