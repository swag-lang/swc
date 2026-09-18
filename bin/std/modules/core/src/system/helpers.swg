#global public

using Swag

// Returns whether `flags` contains at least one bit of `value`.
#[Inline]
func(T) has(flags, value: T)->bool
    where Reflection.isEnum(T)
{
    return flags & value != 0
}

// Returns whether `flags` equals `value` exactly.
#[Inline]
func(T) equals(flags, value: T)->bool
    where Reflection.isEnum(T)
{
    return flags == value
}

// Adds the bits of `value` to the flag set `flags`.
#[Inline]
func(T) add(flags: *T, value: T)
    where Reflection.isEnum(T)
{
    flags[] |= value
}

// Removes the bits of `value` from the flag set `flags`.
#[Inline]
func(T) remove(flags: *T, value: T)
    where Reflection.isEnum(T)
{
    flags[] &= ~value
}

// Replaces the flag set `flags` with `value`.
#[Inline]
func(T) set(flags: *T, value: T)
    where Reflection.isEnum(T)
{
    flags[] = value
}

// Toggles the bits of `value` in the flag set `flags`.
#[Inline]
func(T) toggle(flags: *T, value: T)
    where Reflection.isEnum(T)
{
    flags[] ^= value
}
