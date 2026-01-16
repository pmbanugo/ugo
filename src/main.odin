package main

import sa "core:container/small_array"
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
	// Guards (Checkers)
	// If these fail, the action aborts.
	LT, // assert reg[target] < amount
	EQ, // assert reg[target] == amount
	NEQ, // assert reg[target] != amount

	// Effects (Mutators)
	ASSIGN, // reg[target] = operand (Constant)
	ADD, // reg[target] = reg[src] + operand (Constant)
	SUB, // reg[target] = reg[src] - operand (Constant)

	/* Complex logic (Intrinsics),
	 To solve the DieHarder Water Jug problem cleanly, without a complex math library in the VM (yet)
	*/
	POUR, // Pour from src -> target, capped by 'amount' (capacity of target)
}

Instruction :: struct {
	op:     OpCode,
	target: int, // index of register to write to
	source: int, // index of register to read from (if needed)
	amount: int, // immediate value (literal)
}

// The Evaluator (The VM core)
execute :: proc(s: ^State, instruction: Instruction) -> bool {
	switch instruction.op {
	case .LT:
		value := s.registers[instruction.target].(int)
		if !(value < instruction.amount) do return false

	case .EQ:
		value := s.registers[instruction.target].(int)
		if !(value == instruction.amount) do return false

	case .NEQ:
		value := s.registers[instruction.target].(int)
		if value == instruction.amount do return false

	// --- EFFECTS ---
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

	case .POUR:
		// Logic: transfer = min(from, to_cap - to)
		value_source := s.registers[instruction.source].(int)
		value_target := s.registers[instruction.target].(int)

		space_in_target := instruction.amount - value_target
		transfer := 0

		if value_source < space_in_target {
			transfer = value_source
		} else {
			transfer = space_in_target
		}

		s.registers[instruction.source] = value_source - transfer
		s.registers[instruction.target] = value_target + transfer
	}

	return true
}

// // Execute a single instruction on a state
// execute :: proc(s: ^State, instruction: Instruction) {
// 	// Switch on OpCode to decide behaviour
// 	switch instruction.op {
// 	case .ASSIGN:
// 		s.registers[instruction.target] = instruction.amount
// 	case .ADD:
// 		// We need to extract the integer from the union.
// 		// If it's not an int, this crashes (or we handle error).
// 		// syntax: val.(Type) asserts the type.
// 		current_value := s.registers[instruction.source].(int)
// 		s.registers[instruction.target] = current_value + instruction.amount

// 	case .SUB:
// 		current_value := s.registers[instruction.source].(int)
// 		s.registers[instruction.target] = current_value - instruction.amount
// 	}
// }

// We define a hard limit (e.g., 16 instructions) per action.
// This fits easily in a cache line and requires no heap allocation.
InstructionList :: sa.Small_Array(16, Instruction)
// An Action is a named list of instrutcions
Action :: struct {
	name: string,
	code: InstructionList,
}
// Helper to build an Action from a slice of instructions.
// usage: make_action("Name", []Instruction{ ... })
make_action :: proc(name: string, instructions: []Instruction) -> Action {
	action := Action {
		name = name,
	}

	for instruction in instructions {
		sa.append(&action.code, instruction)
	}
	return action
}

// We use a u64 hash as the map key instead of the State struct itself.
Fingerprint :: u64
fingerprint :: proc(s: State) -> Fingerprint {
	h := u64(0xcbf29ce484222325) // FNV-1a offset basis

	for v in s.registers {
		switch val in v {
		case int:
			// Mix integer into hash
			x := u64(val)
			h = (h ~ x) * 0x100000001b3
		case bool:
			x := u64(val ? 1 : 0)
			h = (h ~ x) * 0x100000001b3
		}
	}
	return Fingerprint(h)
}

reconstruct_path :: proc(
	end_h: Fingerprint,
	parents: map[Fingerprint]Fingerprint,
	storage: map[Fingerprint]State,
) {
	if end_h == parents[end_h] {
		print_state(storage[end_h])
		return
	}
	reconstruct_path(parents[end_h], parents, storage)
	fmt.println("   |")
	fmt.println("   v")
	print_state(storage[end_h])
}

// Test driver
main :: proc() {
	// Setup Water Jug Constant
	SMALL_REG :: 0
	BIG_REG :: 1
	SMALL_JUG_CAP :: 3
	BIG_JUG_CAP :: 5
	TARGET :: 4

	// Define the Actions (The Program)
	// This is what the compiler will eventually generate from the DSL.
	actions := [?]Action { 	// We use a fixed array for the list of actions themselves
		make_action(
			"FillSmall",
			[]Instruction {
				{.LT, SMALL_REG, 0, SMALL_JUG_CAP},
				{.ASSIGN, SMALL_REG, 0, SMALL_JUG_CAP},
			},
		),
		make_action(
			"FillBig",
			[]Instruction{{.LT, BIG_REG, 0, BIG_JUG_CAP}, {.ASSIGN, BIG_REG, 0, BIG_JUG_CAP}},
		),
		make_action(
			"EmptySmall",
			[]Instruction{{.NEQ, SMALL_REG, 0, 0}, {.ASSIGN, SMALL_REG, 0, 0}},
		),
		make_action("EmptyBig", []Instruction{{.NEQ, BIG_REG, 0, 0}, {.ASSIGN, BIG_REG, 0, 0}}),
		make_action("SmallToBig", []Instruction{{.POUR, BIG_REG, SMALL_REG, BIG_JUG_CAP}}),
		make_action("BigToSmall", []Instruction{{.POUR, SMALL_REG, BIG_REG, SMALL_JUG_CAP}}),
	}

	initial_state := State{make([dynamic]Value, 2)}
	initial_state.registers[0] = 0
	initial_state.registers[1] = 0

	// BFS structures
	visited_hashes := make(map[Fingerprint]Fingerprint)
	state_storage := make(map[Fingerprint]State)
	defer delete(state_storage)
	defer delete(visited_hashes)

	start_hash := fingerprint(initial_state)
	visited_hashes[start_hash] = start_hash
	state_storage[start_hash] = initial_state

	queue := make([dynamic]Fingerprint)
	defer delete(queue)
	append(&queue, start_hash)

	fmt.println("Generic Solver Started (Optimized)...")

	found := false
	final_hash: Fingerprint

	// BFS Loop
	loop: for len(queue) > 0 {
		current_hash := queue[0]
		ordered_remove(&queue, 0)
		current_state := state_storage[current_hash]

		// Invariant Check
		if current_state.registers[BIG_REG].(int) == TARGET {
			fmt.println("SOLVED!")
			final_hash = current_hash
			found = true
			break loop
		}

		// Try every action
		for &action in actions {
			next_state := clone_state(current_state)
			possible := true

			// Run Instructions (Iterating the Small_Array)
			// sa.slice(&act.code) gives us a standard slice to iterate
			slice := sa.slice(&action.code)
			for instruction in slice {
				if !execute(&next_state, instruction) {
					possible = false
					break
				}
			}

			if possible {
				h := fingerprint(next_state)
				if h in visited_hashes {
					delete(next_state.registers)
					continue
				}

				visited_hashes[h] = current_hash
				state_storage[h] = next_state
				append(&queue, h)
			} else {
				delete(next_state.registers)
			}
		}
	}

	if found {
		reconstruct_path(final_hash, visited_hashes, state_storage)
	} else {
		fmt.println("No solution found.")
	}
}
