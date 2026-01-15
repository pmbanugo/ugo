package main

import "core:fmt"

// The Atomic Unit of Data
// In TLA, everything is avalue. In our VM, we support these primitives.
Value :: union {
	int,
	bool,
}

// The Generic State
// Instead of named fields, we use a "Register file".
// E.g. In the water jugs problem, index 0 might be "small", index 1 might be "big".
State :: struct {
	registers: [dynamic]Value,
}

// Helper: Deep copy a state because [dynamic] arrays are pointers internally,
clone_state :: proc(s: State) -> State {
	new_state := State {
		registers = make([dynamic]Value, len(s.registers)),
	}

	for value, index in s.registers {
		new_state.registers[index] = value
	}
	return new_state
}

print_state :: proc(state: State) {
	fmt.print("[")
	for value, index in state.registers {
		if index > 0 do fmt.print(", ")
		switch val in value {
		case int:
			fmt.printf("%d", val)
		case bool:
			fmt.printf("%t", val)
		}
		// fmt.printf("{}")
	}
	fmt.println(" ]")
}

// The Instruction Set
OpCode :: enum {
	ASSIGN, // reg[target] = operand (Constant)
	ADD, // reg[target] = reg[src] + operand (Constant)
	SUB, // reg[target] = reg[src] - operand (Constant)
}

Instruction :: struct {
	op:     OpCode,
	target: int, // index of register to write to
	source: int, // index of register to read from (if needed)
	amount: int, // immediate value (literal)
}

// The Evaluator (The VM core)
// Execute a single instruction on a state
execute :: proc(s: ^State, instruction: Instruction) {
	// Switch on OpCode to decide behaviour
	switch instruction.op {
	case .ASSIGN:
		s.registers[instruction.target] = instruction.amount
	case .ADD:
		// We need to extract the integer from the union.
		// If it's not an int, this crashes (or we handle error).
		// syntax: val.(Type) asserts the type.
		current_value := s.registers[instruction.source].(int)
		s.registers[instruction.target] = current_value + instruction.amount

	case .SUB:
		current_value := s.registers[instruction.source].(int)
		s.registers[instruction.target] = current_value - instruction.amount
	}
}

// Test driver
main :: proc() {
	// 1. Initialize state [0, 0] by allocating 2 slots
	initial_state := State{make([dynamic]Value, 2)}
	initial_state.registers[0] = 0 // Small
	initial_state.registers[1] = 0 // Big

	fmt.print("Initial: ")
	print_state(initial_state)

	// 2. Define a proram
	// Goal: small := 3; big := big + 5;
	program := make([dynamic]Instruction, 2)
	program[0] = {
		op     = .ASSIGN,
		target = 0,
		amount = 3,
	} // small = 3
	program[1] = {
		op     = .ADD,
		target = 1,
		source = 1,
		amount = 5,
	} // big = big + 5
	defer delete(program)

	// 3. Run the VM
	// We clone the initial_state so we don't destroy the original
	next_state := clone_state(initial_state)

	fmt.println("Running the programm...")
	for instruction in program {
		execute(&next_state, instruction)
	}

	fmt.print("Final:   ")
	print_state(next_state)

	//Cleanup
	delete(initial_state.registers)
	delete(next_state.registers)
}
