package main

import "core:container/queue"
import sa "core:container/small_array"
import "core:fmt"
import "core:hash/xxhash"
import "core:mem"

REGISTER_SIZE :: 8
// The Register File (just like in a CPU)
// We treat the state as a fixed chunk of memory.
// i64 because it covers pointers and big integers.
// E.g. In the water jugs problem, index 0 might be "small", index 1 might be "big".
State :: struct {
	registers: [REGISTER_SIZE]i64, // fits in a cache line: 8 registers × i64(8 bytes) = 64 bytes
}


print_state :: proc(state: State) {
	fmt.print("[")
	for value, index in state.registers {
		if index > 0 do fmt.print(", ")
		fmt.printf("%d", value)
		// fmt.printf("{}")
	}
	fmt.println(" ]")
}

// The Instruction Set
OpCode :: enum u8 {
	// Guards (Checkers)
	// If these fail, the action aborts.
	LT, // assert registers[target] < amount
	EQ, // assert registers[target] == amount
	NEQ, // assert registers[target] != amount

	// Effects (Mutators)
	ASSIGN, // registers[target] = amount
	ADD, // registers[target] = registers[src] + amount
	SUB, // registers[target] = registers[src] - amount

	// Complex logic (Intrinsics), To solve the DieHarder Water Jug problem cleanly, without a complex math library in the VM (yet)
	POUR, // Pour from src -> target, capped by 'amount' (capacity of target)
}

Instruction :: struct {
	amount: i64, // immediate value
	op:     OpCode,
	target: u8, // index of register to write to
	source: u8, // index of register to read from (if needed)
}

// The Evaluator (The VM core)
execute :: proc(s: ^State, instruction: Instruction) -> bool {
	switch instruction.op {
	case .LT:
		value := s.registers[instruction.target]
		if !(value < instruction.amount) do return false

	case .EQ:
		value := s.registers[instruction.target]
		if !(value == instruction.amount) do return false

	case .NEQ:
		value := s.registers[instruction.target]
		if value == instruction.amount do return false

	// --- EFFECTS ---
	case .ASSIGN:
		s.registers[instruction.target] = instruction.amount
	case .ADD:
		// We need to extract the integer from the union.
		// If it's not an int, this crashes (or we handle error).
		// syntax: val.(Type) asserts the type.
		current_value := s.registers[instruction.source]
		s.registers[instruction.target] = current_value + instruction.amount
	case .SUB:
		current_value := s.registers[instruction.source]
		s.registers[instruction.target] = current_value - instruction.amount

	case .POUR:
		// Logic: transfer = min(from, to_cap - to)
		value_source := s.registers[instruction.source]
		value_target := s.registers[instruction.target]

		space_in_target := instruction.amount - value_target
		transfer: i64 = min(value_source, space_in_target)

		s.registers[instruction.source] = value_source - transfer
		s.registers[instruction.target] = value_target + transfer
	}

	return true
}

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

Fingerprint :: u64
fingerprint :: proc(s: ^State) -> Fingerprint {
	// AFAIU this is zero-copy
	// It creates a slice view of the struct's memory: { ptr=s, len=64 }.
	// This is safe because it's a fixed array of integers.
	data := mem.ptr_to_bytes(s)

	/* Use XXH3. This will compile down to SIMD instructions (SSE2/AVX)
       making it incredibly fast for our 64-byte State struct.
    */
	return xxhash.XXH3_64(data)
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
				{SMALL_JUG_CAP, .LT, SMALL_REG, 0},
				{SMALL_JUG_CAP, .ASSIGN, SMALL_REG, 0},
			},
		),
		make_action(
			"FillBig",
			[]Instruction{{BIG_JUG_CAP, .LT, BIG_REG, 0}, {BIG_JUG_CAP, .ASSIGN, BIG_REG, 0}},
		),
		make_action(
			"EmptySmall",
			[]Instruction{{0, .NEQ, SMALL_REG, 0}, {0, .ASSIGN, SMALL_REG, 0}},
		),
		make_action("EmptyBig", []Instruction{{0, .NEQ, BIG_REG, 0}, {0, .ASSIGN, BIG_REG, 0}}),
		make_action("SmallToBig", []Instruction{{BIG_JUG_CAP, .POUR, BIG_REG, SMALL_REG}}),
		make_action("BigToSmall", []Instruction{{SMALL_JUG_CAP, .POUR, SMALL_REG, BIG_REG}}),
	}

	initial_state := State{}
	initial_state.registers[0] = 0
	initial_state.registers[1] = 0

	// BFS structures
	visited_hashes := make(map[Fingerprint]Fingerprint)
	state_storage := make(map[Fingerprint]State)
	defer delete(state_storage)
	defer delete(visited_hashes)

	start_hash := fingerprint(&initial_state)
	visited_hashes[start_hash] = start_hash
	state_storage[start_hash] = initial_state

	queue_fingerprint: queue.Queue(Fingerprint)
	queue.init(&queue_fingerprint)
	defer queue.destroy(&queue_fingerprint)
	queue.push(&queue_fingerprint, start_hash)

	fmt.println("Generic Solver Started (Optimized)...")

	found := false
	final_hash: Fingerprint

	// BFS Loop
	loop: for queue.len(queue_fingerprint) > 0 {
		current_hash := queue.pop_front(&queue_fingerprint)
		current_state := state_storage[current_hash]

		// Invariant Check
		if current_state.registers[BIG_REG] == TARGET {
			fmt.println("SOLVED!")
			final_hash = current_hash
			found = true
			break loop
		}

		// Try every action
		for &action in actions {
			next_state := current_state
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
				state_fingerprint := fingerprint(&next_state)
				if state_fingerprint in visited_hashes do continue

				// New state found
				visited_hashes[state_fingerprint] = current_hash // point back to parent
				state_storage[state_fingerprint] = next_state
				queue.push(&queue_fingerprint, state_fingerprint)
			}
		}
	}

	if found {
		reconstruct_path(final_hash, visited_hashes, state_storage)
	} else {
		fmt.println("No solution found.")
	}
}
