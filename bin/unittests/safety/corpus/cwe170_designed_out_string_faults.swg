#global private

using Swag
using Corpus

// -----------------------------------------------------------------------------
// CWE-170 (improper null termination), CWE-134 (format string), CWE-125 on strings
//
// Three families that dominate the C corpora and have no Swag form at all. They are kept
// rather than omitted: a corpus that lists only what a language checks, and never what it
// makes unwritable, measures the analysis instead of the language.
//
// - CWE-170: a 'string' carries its byte count. There is no terminator to forget, no
//   'strcpy' that stops at the wrong byte, and no length that has to be recomputed by
//   scanning. The class needs a representation Swag does not have.
// - CWE-134: formatting is typed. The format string and its arguments are checked together,
//   so an argument list that does not match what the format asks for is a compile-time
//   error rather than a walk up the stack.
// - CWE-785 and friends: there is no fixed-size path buffer in the language surface.
//
// What remains reachable is the 'cstring' boundary, which exists precisely to talk to C - and
// that is where the marker belongs rather than here.
// -----------------------------------------------------------------------------

// --- Sound: the properties the absence rests on ---

func stringCarriesItsCount()->bool
{
    let text = "abc"
    return text.count == 3
}

// A string containing an interior zero keeps its full length: nothing stops at the byte.
func interiorZeroDoesNotTerminate()->bool
{
    let text = "a\0b"
    return text.count == 3 and text[1] == 0 and text[2] == 'b'
}

// Slicing a string produces a string with its own count, not a pointer into a terminated
// buffer, so there is no sub-string that can outlive its length.
func sliceKeepsItsOwnCount()->bool
{
    let text  = "abcdef"
    let piece = text[1 until 4]
    return piece.count == 3 and piece[0] == 'b'
}

// An empty string is present, not absent: emptiness is a count, nullability is the '?' suffix.
// Conflating the two is what produces a null-terminator bug in C.
func emptyIsNotNull()->bool
{
    let text: string = ""
    return text.count == 0
}

// Indexing a string is bound-checked like any other sized value, so reading past the end
// cannot walk to the next terminator.
#[Swag.Safety(.BoundCheck, true)]
func readPastEndOfString(index: u64)->u8
{
    let text = "abc"
    return text[index]     // swc-expected-error {{safety_err_runtime}}
}

#test
{
    #run readPastEndOfString(opaqueU64(3))
}

#test
{
    Swag.assert(stringCarriesItsCount())
    Swag.assert(interiorZeroDoesNotTerminate())
    Swag.assert(sliceKeepsItsOwnCount())
    Swag.assert(emptyIsNotNull())
}
