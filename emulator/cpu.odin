package emulator

import "core:fmt"

PROGRAM_START :: 0x200

CHIP8_WIDTH :: 64
CHIP8_HEIGHT :: 32

Chip :: struct {
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

pixel_index :: proc(x, y: u16) -> u16 {
	return x + y * CHIP8_WIDTH
}

Opcode :: enum {
	Unknown, // 0
	Cls, // Clear the display
	Ret, // Return from subroutine
	Jp_addr, // Jump to location nnn
	Call_addr, // Call subroutine at nnn
	Se_vx_byte, // Skip next instruction if Vx = nn
	Sne_vx_byte, // Skip next instruction if Vx != nn
	Se_vx_vy, // Skip next instruction if Vx = Vy
	Ld_vx_byte, // Set Vx = nn
	Add_vx_byte, // Set Vx = Vx + nn
	Ld_i_addr, // Set I = nnn
	Drw_vx_vy_n, // Display n-byte sprite starting at memory location I at (Vx, Vy)
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

// http://devernay.free.fr/hacks/chip8/C8TECH10.HTM#3.1
DECODER_RULES :: [?]Rule {
	{0xFFFF, 0x00E0, .Cls}, // 00E0
	{0xFFFF, 0x00EE, .Ret}, // 00EE
	{0xF000, 0x1000, .Jp_addr}, // 1nnn
	{0xF000, 0x2000, .Call_addr}, // 2nnn
	{0xF000, 0x3000, .Se_vx_byte}, // 3xnn
	{0xF000, 0x4000, .Sne_vx_byte}, // 4xnn
	{0xF00F, 0x5000, .Se_vx_vy}, // 5xy0
	{0xF000, 0x6000, .Ld_vx_byte}, // 6xnn
	{0xF000, 0x7000, .Add_vx_byte}, // 7xnn
	{0xF000, 0xA000, .Ld_i_addr}, // Annn
	{0xF000, 0xD000, .Drw_vx_vy_n}, // Dxyn
}

read_opcode :: proc(chip: ^Chip, addr: u16) -> (opcode: u16, ok: bool) {
	if addr >= len(chip.memory) - 1 {
		return
	}

	hi := u16(chip.memory[addr])
	low := u16(chip.memory[addr + 1])
	opcode = (hi << 8) | low
	ok = true
	return
}

fetch :: proc(chip: ^Chip) -> (opcode: u16, ok: bool) {
	// Fetch the instruction under PC and update the PC.
	opcode, ok = read_opcode(chip, chip.pc)
	if !ok {return}
	chip.pc += 2
	return
}

decode :: proc(bin_insn: u16) -> (insn: Instruction) {
	insn = Instruction {
		raw = bin_insn,
		nnn = bin_insn & 0x0FFF,
		nn  = u8(bin_insn & 0xFF),
		n   = u8(bin_insn & 0xF),
		x   = u8(bin_insn >> 8 & 0xF),
		y   = u8(bin_insn >> 4 & 0xF),
	}

	for r in DECODER_RULES {
		if (bin_insn & r.mask) == r.value {
			insn.opcode = r.opcode
			return
		}
	}

	// As .Unknown is the first value of the enum it is the default one.
	// If we are here then .Unknown is returned.
	return
}

Exec_Error :: enum {
	None,
	Not_Implemented,
	Unknown_Opcode,
}

execute :: proc(insn: ^Instruction, chip: ^Chip) -> Exec_Error {
	#partial switch insn.opcode {
	case .Unknown:
		return .Unknown_Opcode
	case .Add_vx_byte:
		chip.v[insn.x] += insn.nn
		return .None
	case .Cls:
		chip.graphics = {}
		return .None
	case .Jp_addr:
		chip.pc = insn.nnn
		return .None
	case .Ld_i_addr:
		chip.i = insn.nnn
		return .None
	case .Ld_vx_byte:
		chip.v[insn.x] = insn.nn
		return .None
	case .Drw_vx_vy_n:
		// It draws a sprite of n bytes (width is always 8 pixels) starting at
		// memory location I at (Vx, Vy).
		// NOTE: Reference disagree on what happens at the screen edges.
		// Cowgod's reference says the sprite wraps around to the opposite side.
		// The original COSMAC VIP (and Timendus'test suite) does two different things:
		//   - the starting position wraps: Vx/Vy are masked to the screen size,
		//   - the drawing is clipped: pixels going past the right/bottom edge are not drawn.
		// We follow the original behavior
		x := cast(u16)chip.v[insn.x] % CHIP8_WIDTH
		y := cast(u16)chip.v[insn.y] % CHIP8_HEIGHT

		// Reset VF. Don't reset it before in case of X or Y is equal to 0xF...
		chip.v[0xf] = 0

		for idx in 0 ..< insn.n {
			idx_16 := cast(u16)idx
			row := chip.memory[chip.i + idx_16]

			for p in 0 ..= 7 {
				// Clipping, see the note above.
				px := x + cast(u16)p
				if px >= CHIP8_WIDTH {continue}
				py := y + cast(u16)idx
				if py >= CHIP8_HEIGHT {continue}

				sprite_bit := row & (0b10000000 >> cast(uint)p)
				old := chip.graphics[pixel_index(px, py)]

				// Regarding the bit of the sprite, a value different from 0
				// means we toggle the old value, 0 means we don't.
				// A pixel erased will set VF to 1.
				if sprite_bit != 0 {
					// We switch
					if old {
						// old was on, erased it
						chip.graphics[pixel_index(px, py)] = false
						chip.v[0xf] = 1
					} else {
						// Just set the bit
						chip.graphics[pixel_index(px, py)] = true
					}
				}
				// else branch is we don't switch, so nothing to do
			}
		}
		return .None
	case:
		return .Not_Implemented
	}
}

disassemble :: proc(insn: ^Instruction, output: []u8) -> string {
	switch insn.opcode {
	case .Unknown:
		return fmt.bprintf(output, "???")
	case .Cls:
		return fmt.bprintf(output, "CLS")
	case .Ret:
		return fmt.bprintf(output, "RET")
	case .Jp_addr:
		return fmt.bprintf(output, "JP 0x%03x", insn.nnn)
	case .Call_addr:
		return fmt.bprintf(output, "CALL 0x%03x", insn.nnn)
	case .Se_vx_byte:
		return fmt.bprintf(output, "SE V%X, 0x%02x", insn.x, insn.nn)
	case .Sne_vx_byte:
		return fmt.bprintf(output, "SNE V%X, 0x%02x", insn.x, insn.nn)
	case .Se_vx_vy:
		return fmt.bprintf(output, "SE V%X, V%X", insn.x, insn.y)
	case .Ld_vx_byte:
		return fmt.bprintf(output, "LD V%X, 0x%02x", insn.x, insn.nn)
	case .Add_vx_byte:
		return fmt.bprintf(output, "ADD V%X, 0x%02x", insn.x, insn.nn)
	case .Ld_i_addr:
		return fmt.bprintf(output, "LD I, 0x%03x", insn.nnn)
	case .Drw_vx_vy_n:
		return fmt.bprintf(output, "DRW V%X, V%X, 0x%02x", insn.x, insn.y, insn.n)
	}

	return fmt.bprintf(output, "UNREACHABLE")
}
