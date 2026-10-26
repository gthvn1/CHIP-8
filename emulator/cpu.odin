package emulator

import "core:fmt"

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

fetch :: proc(state: ^State) -> u16 {
	// Fetch the instruction under PC and update the PC.
	hi := u16(state.memory[state.pc])
	low := u16(state.memory[state.pc + 1])
	return (hi << 8) | low
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

execute :: proc(insn: ^Instruction, state: ^State) {
	#partial switch insn.opcode {
	case .Clear:
		state.pc += 2
	case:
		fmt.eprintln("Instruction not implemented")
	}

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
