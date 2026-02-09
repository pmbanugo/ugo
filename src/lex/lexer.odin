package lex

import "../core"
import "core:unicode/utf8"

/*--------------------------
  String Interner
  --------------------------
*/

// Interner maps string content to unique IDs
Interner :: struct {
	// Map: Source String View -> Unique ID
	lookup: map[string]core.String_Id,
	// Table: ID -> String View
	// We use [dynamic] for O(1) random access lookup speed.
	// We do not use Xar because we don't need pointer stability (we use Integer Handles).
	table:  [dynamic]string,
}

init_interner :: proc(interner: ^Interner, allocator := context.allocator) {
	// Initialise map with a reasonable capacity to avoid early resizing
	interner.lookup = make(map[string]core.String_Id, 1024, allocator)
	interner.table = make([dynamic]string, allocator)

	// STRATEGY: Zero Is Valid (The "Sentinel" at 0).
	// We explicitly push an empty string to Index 0.
	// This ensures String_Id(0) safely resolves to "".
	append(&interner.table, "")
	interner.lookup[""] = core.EMPTY_STRING_ID
}

destroy_interner :: proc(interner: ^Interner) {
	delete(interner.lookup)
	delete(interner.table)
}

// adds the text to the pool if it's new, or returns the exisitng ID
intern :: proc(interner: ^Interner, text: string) -> core.String_Id {
	if id, ok := interner.lookup[text]; ok {
		return id
	}

	id := core.String_Id(len(interner.table))
	append(&interner.table, text)
	interner.lookup[text] = id
	return id
}

/*--------------------------
  Lexer
  --------------------------
*/

// Whitespace bitset for O(1) membership testing (Stolen from Odin core)
// Only allows for ASCII whitespace
// utf8.RUNE_SELF is 0x80 (128), so '..<' means 0 to 127
Whitespace :: distinct bit_set['\x00'..<utf8.RUNE_SELF; u128]
IS_WHITESPACE :: Whitespace{' ', '\t', '\r', '\n'}

Lexer :: struct {
	source:       string,
	interner:     ^Interner,

	// stores the result as #soa [dynamic]Token:
	// 1 Cache Locality: 'Kind' array is packed tight for the Parser.
	// 2. Simplicity: Easier to use than Xar for this access pattern, and possible SIMD ops
	tokens:       #soa[dynamic]Token,

	// A side-table of line-start offsets.
	// Used to calculate Line:Column on demand without bloating the Token struct.
	line_offsets: [dynamic]u32,

	// Internal offsets are u32 to match core.Span, avoiding casts in the tokenize loop.
	offset:       u32, // current byte offset
	read_offset:  u32, // next byte offset
	character:    rune, // current unicode character
}

init_lexer :: proc(
	lexer: ^Lexer,
	interner: ^Interner,
	source: string,
	allocator := context.allocator,
) {
	// Ensure the file fits in our deterministic u32 types (See core.Span).
	// Fail fast if assumptions are violated.
	assert(len(source) <= 0xFFFFFFFF, "Source file too large (max 4GB)")

	lexer.source = source
	lexer.interner = interner

	// Pre-allocate storage
	lexer.tokens = make(#soa[dynamic]Token, 0, 1024, allocator)
	lexer.line_offsets = make([dynamic]u32, 0, 128, allocator)

	// Line 1 always starts at offset 0
	append(&lexer.line_offsets, 0)

	// Prime the lexer state
	lexer.offset = 0
	lexer.read_offset = 0

	// Skip UTF-8 BOM if present
	if len(lexer.source) >= 3 && lexer.source[0:3] == "\xEF\xBB\xBF" {
		lexer.read_offset = 3
	}

	advance(lexer)
}

destroy_lexer :: proc(lexer: ^Lexer) {
	delete(lexer.tokens)
	delete(lexer.line_offsets)
}

// advance consumes the current character and loads the next.
// Updates offset, read_offset and character.
advance :: proc(lexer: ^Lexer) {
	// If the current character we are leaving is a newline, the next char starts a new line.
	if lexer.character == '\n' {
		append(&lexer.line_offsets, lexer.read_offset)
	}

	if int(lexer.read_offset) >= len(lexer.source) {
		lexer.character = 0 // EOF sentinel
		lexer.offset = u32(len(lexer.source))
		lexer.read_offset = u32(len(lexer.source) + 1)
	} else {
		lexer.offset = lexer.read_offset

		// Indexing requires int, but we keep internal offsets as u32.
		// We cast to int here (once per character) to support library calls.
		r, w := utf8.decode_rune_in_string(lexer.source[int(lexer.read_offset):])
		lexer.character = r
		lexer.read_offset += u32(w)
	}
}

// returns the next character without advancing the state
peek :: proc(lexer: ^Lexer) -> rune {
	if int(lexer.read_offset) >= len(lexer.source) do return 0
	r, _ := utf8.decode_rune_in_string(lexer.source[int(lexer.read_offset):])
	return r
}

// "Push For loops Down": Consumes all non-token text (whitespace & comments).
// It centralizes the logic for "skipping stuff" so the main loop is clean.
skip_whitespace_and_comments :: proc(lexer: ^Lexer) {
	loop: for {
		// Use bit-set for fast whitespace check
		if lexer.character < 128 && lexer.character in IS_WHITESPACE {
			advance(lexer)
			continue
		}

		if lexer.character == '/' {
			next := peek(lexer)
			if next == '/' {
				// Line comment: consume until newline
				advance(lexer)
				advance(lexer)
				for lexer.character != '\n' && lexer.character != 0 {
					advance(lexer)
				}
				continue
			} else if next == '*' {
				// Block comment: consume until */
				advance(lexer)
				advance(lexer)
				for lexer.character != 0 {
					if lexer.character == '*' && peek(lexer) == '/' {
						advance(lexer)
						advance(lexer)
						break
					}
					advance(lexer)
				}
				continue
			}
		}

		break loop
	}
}

// process the entire source string into the tokens array
tokenize :: proc(lexer: ^Lexer) {
	for lexer.character != 0 {
		// 1. Consume non-token text
		skip_whitespace_and_comments(lexer)
		if lexer.character == 0 do break

		start := lexer.offset
		kind := Token_Kind.Invalid
		payload: u64 = 0

		// 2. control flow for character dispatch
		switch lexer.character {
		// --- Delimiters ---
		case '{':
			kind = .L_Brace; advance(lexer)
		case '}':
			kind = .R_Brace; advance(lexer)
		case '(':
			kind = .L_Paren; advance(lexer)
		case ')':
			kind = .R_Paren; advance(lexer)
		case '[':
			kind = .L_Bracket; advance(lexer)
		case ']':
			kind = .R_Bracket; advance(lexer)
		case ',':
			kind = .Comma; advance(lexer)
		case '\'':
			kind = .Prime; advance(lexer)

		// --- Operators ---
		case ':':
			advance(lexer)
			if lexer.character == '=' {
				kind = .Assignment
				advance(lexer)
			} else {
				kind = .Colon
			}

		case '=':
			advance(lexer)
			if lexer.character == '=' {
				kind = .Equality
				advance(lexer)
			} else if lexer.character == '>' {
				kind = .Implication
				advance(lexer)
			} else {
				// The Parser will enforce that it isn't used in logic/effects.
				kind = .Definition
			}

		case '!':
			advance(lexer)
			if lexer.character == '=' {
				kind = .Inequality
				advance(lexer)
			} else {
				kind = .Not
			}

		case '&':
			advance(lexer)
			if lexer.character == '&' {
				kind = .And
				advance(lexer)
			} else {
				kind = .Ampersand
			}

		case '|':
			advance(lexer)
			if lexer.character == '|' {
				kind = .Or
				advance(lexer)
			} else {
				kind = .Pipe
			}

		case '<':
			advance(lexer)
			if lexer.character == '=' {
				advance(lexer)
				if lexer.character == '>' {
					kind = .Equivalence
					advance(lexer)
				} else {
					kind = .Less_Than_Or_Equal
				}
			} else {
				kind = .Less_Than
			}

		case '>':
			advance(lexer)
			if lexer.character == '=' {
				kind = .Greater_Than_Or_Equal
				advance(lexer)
			} else {
				kind = .Greater_Than
			}

		case '-':
			advance(lexer)
			if lexer.character == '>' {
				kind = .Arrow
				advance(lexer)
			} else {
				kind = .Minus
			}

		case '+':
			advance(lexer)
			if lexer.character == '+' {
				kind = .Plus_Plus
				advance(lexer)
			} else {
				kind = .Plus
			}

		case '*':
			kind = .Star; advance(lexer)
		case '/':
			kind = .Slash; advance(lexer)
		case '\\':
			kind = .Backslash; advance(lexer)

		case '.':
			advance(lexer)
			if lexer.character == '.' {
				kind = .Dot_Dot
				advance(lexer)
			} else {
				kind = .Dot
			}

		// --- String Literal ---
		case '"':
			kind = .String
			advance(lexer)
			for lexer.character != '"' && lexer.character != 0 {
				if lexer.character == '\\' do advance(lexer)
				advance(lexer)
			}
			if lexer.character == '"' do advance(lexer)

		case:
			if is_letter(lexer.character) {
				// --- Identifier/Keyword ---
				for is_letter(lexer.character) || is_digit(lexer.character) {
					advance(lexer)
				}

				text := lexer.source[int(start):int(lexer.offset)]
				kind = resolve_keyword(text)

				if kind == .Identifier {
					id := intern(lexer.interner, text)
					payload = u64(id)
				}

			} else if is_digit(lexer.character) {
				// --- Integer Literal ---
				kind = .Integer
				for is_digit(lexer.character) {
					advance(lexer)
				}
			} else {
				kind = .Invalid
				advance(lexer)
			}
		}

		append(
			&lexer.tokens,
			Token {
				kind = kind,
				span = core.Span{offset = start, length = lexer.offset - start},
				payload = payload,
			},
		)
	}

	// Append EOF token
	append(&lexer.tokens, Token{kind = .EOF, span = {lexer.offset, 0}})
}

// --- Position Helper (Side-Table Query) ---
// This is only called when reporting errors, keeping the hot path clean.
get_position :: proc(lexer: ^Lexer, offset: u32) -> (line: u32, column: u32) {
	line = 1
	line_start_offset: u32 = 0

	// Binary search or linear scan through the side-table to find the line
	for start_offset, idx in lexer.line_offsets {
		if start_offset > offset do break
		line = u32(idx + 1)
		line_start_offset = start_offset
	}

	// Column is simply the delta from the start of the line
	column = (offset - line_start_offset) + 1
	return
}

// --- Helpers ---
@(private = "file")
is_letter :: proc(c: rune) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

@(private = "file")
is_digit :: proc(c: rune) -> bool {
	return c >= '0' && c <= '9'
}

@(private = "file")
resolve_keyword :: proc(text: string) -> Token_Kind {
	switch text {
	case "module":
		return .Module
	case "types":
		return .Types
	case "constants":
		return .Constants
	case "state":
		return .State
	case "init":
		return .Init
	case "actions":
		return .Actions
	case "action":
		return .Action
	case "system":
		return .System
	case "properties":
		return .Properties
	case "next":
		return .Next
	case "until":
		return .Until
	case "enabled":
		return .Enabled
	case "effect":
		return .Effect
	case "pick":
		return .Pick
	case "safety":
		return .Safety
	case "invariant":
		return .Invariant
	case "bounded":
		return .Bounded
	case "reachability":
		return .Reachability
	case "within":
		return .Within
	case "predicate":
		return .Predicate
	case "unchanged":
		return .Unchanged
	case "forall":
		return .Forall
	case "exists":
		return .Exists
	case "if":
		return .If
	case "then":
		return .Then
	case "else":
		return .Else
	case "in":
		return .In
	case "true":
		return .Boolean
	case "false":
		return .Boolean
	case "mod":
		return .Mod

	case "Integer":
		return .Type_Integer
	case "Boolean":
		return .Type_Boolean
	case "Natural":
		return .Type_Natural
	case "Range":
		return .Type_Range
	case "Set":
		return .Type_Set
	case "Sequence":
		return .Type_Sequence
	case "Map":
		return .Type_Map
	case "Record":
		return .Type_Record
	case "Enum":
		return .Type_Enum

	case:
		return .Identifier
	}
}
