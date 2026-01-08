package main

import "core:fmt"

// 1. The Constants (The Rules of the Universe)
SMALL_CAP :: 3
BIG_CAP :: 5
TARGET :: 4

// 2. The State Vector
// We use 'distinct' to ensure we don't accidentally mix up gallons with other integers.
Gallons :: distinct int

State :: struct {
	small: Gallons,
	big:   Gallons,
}

main :: proc() {
	initial_state := State{0, 0}
	fmt.printf("Goal: Reach %d gallons in the big jug.\n", TARGET)
	fmt.println("Initial State: ")
	print_state(initial_state)

	// 1. Queue for Breadth-first search (BFS)
	queue := make([dynamic]State)
	defer delete(queue)
	append(&queue, initial_state)

	// 2. Visited map (State -> Parent Sate)
	// We use this to reconstruct the path later.
	// If a state is in this map, it has been visited.
	visited := make(map[State]State)
	defer delete(visited)

	// Mark initial state as visited
	// We use the initial state as its own parent to mark the start.
	visited[initial_state] = initial_state

	fmt.println("Starting Solver...")

	found := false
	final_state: State

	// BFS loop
	for len(queue) > 0 {
		// Pop from front (inefficient in dynamic array, but fine for now)
		current := queue[0]
		ordered_remove(&queue, 0) // Removes index 0 and shifts everything down

		// INVARIANT CHECK: Did we win?
		if current.big == TARGET {
			fmt.println("SOLVED! Found a state with 4 gallons.")
			final_state = current
			found = true
			break
		}

		// Generate next states
		next_candidates := next_states(current)
		defer delete(next_candidates) //Clean up the temporary list from get_next_states()

		for next in next_candidates {
			// Check if we have seen this state before
			if next in visited {
				continue
			}

			// New state found!
			visited[next] = current // Record path
			append(&queue, next)
		}
	}

	if found {
		print_trace(final_state, visited)
	} else {
		fmt.println("Impossible to solve.")
	}
}

// Helper to print state nicely
print_state :: proc(s: State) {
	fmt.printf("[ small: {}, big: {} ]\n", s.small, s.big)
}

// Returns a list of all possible next states from a given state
next_states :: proc(s: State) -> [dynamic]State {
	states := make([dynamic]State)

	// Rule 1: Fill Small Jug
	append(&states, State{Gallons(SMALL_CAP), s.big})

	// Rule 2: Fill Big Jug
	append(&states, State{s.small, Gallons(BIG_CAP)})

	// Rule 3: Empty Small Jug
	append(&states, State{0, s.big})

	// Rule 4: Empty Big Jug
	append(&states, State{s.small, 0})

	// Rule 5: Small to Big
	// We pour from small to big until either small is empty OR big is full.
	// This requires a bit of math (min/max).
	// Let's implement this logic explicitly.
	{
		amount_to_pour := min(s.small, BIG_CAP - s.big)
		new_small := s.small - amount_to_pour
		new_big := s.big + amount_to_pour
		append(&states, State{Gallons(new_small), Gallons(new_big)})
	}

	// Rule 6: Big to Small
	{
		amount_to_pour := min(s.big, SMALL_CAP - s.small)
		new_small := s.small + amount_to_pour
		new_big := s.big - amount_to_pour
		append(&states, State{Gallons(new_small), Gallons(new_big)})
	}

	return states
}

print_trace :: proc(end: State, parents: map[State]State) {
	if end == parents[end] {
		// We reached the start
		print_state(end)
		return
	}

	parent := parents[end]
	print_trace(parent, parents) // Recurse first to print in order
	fmt.println("   |   ")
	fmt.println("   v   ")
	print_state(end)
}
