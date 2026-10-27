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

	// As .Unkown is the first value of the enum it is the default one.
	// If we are here then .Unkown is returned.
	return
}

execute :: proc(insn: ^Instruction, chip: ^Chip) {
	#partial switch insn.opcode {
	case .Clear:
		fmt.eprintln("TODO: clear the screen")
	case:
		fmt.eprintln("Instruction not implemented")
	}

}

disassemble :: proc(insn: ^Instruction, output: []u8) -> string {
	switch insn.opcode {
	case .Unknown:
		return fmt.bprintf(output, "UNKN")
	case .Clear:
		return fmt.bprintf(output, "CLR")
	case .Return:
		return fmt.bprintf(output, "RET")
	case .Jump:
		return fmt.bprintf(output, "JMP 0x%03x", insn.nnn)
	case .Call:
		return fmt.bprintf(output, "CALL 0x%03x", insn.nnn)
	case .Seq:
		return fmt.bprintf(output, "SEQ V[%d] 0x%x", insn.x, insn.nn)
	case .Sneq:
		return fmt.bprintf(output, "SNEQ V[%d] 0x%x", insn.x, insn.nn)
	case .Sveq:
		return fmt.bprintf(output, "SVEQ V[%d] V[%d]", insn.x, insn.y)
	case .Set:
		return fmt.bprintf(output, "SET V[%d] 0x%x", insn.x, insn.nn)
	case .Add:
		return fmt.bprintf(output, "ADD V[%d] 0x%x", insn.x, insn.nn)
	}

	return fmt.bprintf(output, "UNREACHABLE")
}
