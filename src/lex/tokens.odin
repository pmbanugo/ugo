package lex

import "../core"

// We do not store the string text here. We point to the source.
Token :: struct {
	payload: u64, // Interned String_Id or raw value
	span:    core.Span,
	kind:    Token_Kind,
}

Token_Kind :: enum u8 {
	// --- Special ---
	Invalid = 0, // Zero-init safety
	EOF,
	Comment,

	// --- Literals ---
	Identifier,
	Integer,
	String,
	Boolean, // true, false

	// --- Structural Keywords ---
	Module, // module
	Types, // types
	Constants, // constants
	State, // state
	Init, // init
	Actions, // actions
	Action, // action
	System, // system
	Properties, // properties

	// --- Behavioral Keywords ---
	Next, // next
	Until, // until
	Enabled, // enabled
	Effect, // effect
	Pick, // pick
	Safety, // safety
	Invariant, // invariant
	Bounded, // bounded
	Reachability, // reachability
	Within, // within
	Predicate, // predicate
	Unchanged, // unchanged
	Forall, // forall
	Exists, // exists
	If, // if
	Then, // then
	Else, // else
	In, // in

	// --- Type Keywords ---
	Type_Integer, // Integer
	Type_Boolean, // Boolean
	Type_Natural, // Natural
	Type_Range, // Range
	Type_Set, // Set
	Type_Sequence, // Sequence
	Type_Map, // Map
	Type_Record, // Record
	Type_Enum, // Enum

	// --- Punctuation ---
	L_Brace, // {
	R_Brace, // }
	L_Paren, // (
	R_Paren, // )
	L_Bracket, // [
	R_Bracket, // ]
	Colon, // :
	Comma, // ,
	Dot, // .
	Dot_Dot, // ..
	Arrow, // ->
	Definition, // = (Static Definitions: Types, Constants)

	// --- Operators ---
	Assignment, // :=  (State Update)
	Prime, // '   (Next state variable)
	Equality, // ==  (Equality)
	Inequality, // !=
	Less_Than, // <
	Less_Than_Or_Equal, // <=
	Greater_Than, // >
	Greater_Than_Or_Equal, // >=
	And, // &&
	Or, // ||
	Implication, // =>
	Equivalence, // <=>
	Plus, // +
	Minus, // -
	Star, // *
	Slash, // /
	Mod, // mod
	Not, // !
	Pipe, // |   (Set Union)
	Ampersand, // &   (Set Intersection)
	Backslash, // \   (Set Difference)
	Plus_Plus, // ++  (Seq Concat)
}
