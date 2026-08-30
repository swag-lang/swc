#global private

/**
# Data at a C ABI Boundary

'cstring' represents a zero-terminated byte string. Swag's ordinary 'string'
stores an explicit byte count and may contain embedded zeroes, so crossing the
ABI boundary should be an intentional conversion. String-literal storage has a
trailing zero; take its data pointer before casting that pointer to 'cstring'.
*/

#test
{
    let literal = "Swag"
    let text    = cast(const cstring) literal.buffer
    Swag.assert(text.count == 4)
    Swag.assert(text[0] == 'S'u8)
    Swag.assert(text[3] == 'g'u8)
}

/**
For other data:

- Prefer 's8' through 's64' and 'u8' through 'u64' over platform-dependent C
  spellings.
- Represent optional C pointers with '#null *T' or '#null const *T'.
- Match aggregate packing and alignment with '#[Swag.Pack]' and
  '#[Swag.Align]' only when the external ABI requires it.
- State who owns returned memory and which function releases it.
- Treat a returned pointer as borrowed unless the external API explicitly
  transfers ownership.
*/
