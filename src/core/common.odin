package core

// Span represents a slice of the source text
// We use a zero-copy approach: storing offset/index and length rather than copying strings.
// Uses u32 because:
// 1. Deterministic size (8 bytes total) regardless of architecture.
// 2. Memory efficiency (fits more tokens in cache).
// 3. Semantic correctness (cannot be negative).
Span :: struct {
	offset: u32,
	length: u32,
}

// Helper to get slice bound bounds as native integers for indexing.
@(require_results)
span_range :: proc(s: Span) -> (int, int) {
	return int(s.offset), int(s.offset + s.length)
}

// Distinct handle types for compile-time safety. These are indices into their respective arrays
Token_Id :: distinct u32
String_Id :: distinct u32

// RESERVED ID: 0
// Index 0 in the interner is guaranteed to hold a valid empty string "".
// This ensures that zero-initialized string point to safe, valid data.
EMPTY_STRING_ID :: String_Id(0)
