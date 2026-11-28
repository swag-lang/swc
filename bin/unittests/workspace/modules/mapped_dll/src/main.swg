#global public

// Reached at compile time through the shared library: neither inlined nor generic, so the call
// maps the library in the compiler that makes it.
#[Swag.NoInline]
func mappedDllValue()->s32 => 42
