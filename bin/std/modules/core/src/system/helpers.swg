#global public

using Swag

// Returns whether every bit in value is present in flags.
#[Inline]
func(T) has(flags, value: T)->bool
    where Reflection.isEnum(T)
{
    return flags & value != 0
}

// Returns whether flags contains exactly value.
#[Inline]
func(T) equals(flags, value: T)->bool
    where Reflection.isEnum(T)
{
    return flags == value
}

// Adds value to a flag set.
#[Inline]
func(T) add(flags: *T, value: T)
    where Reflection.isEnum(T)
{
    dref flags |= value
}

// Removes value from a flag set.
#[Inline]
func(T) remove(flags: *T, value: T)
    where Reflection.isEnum(T)
{
    dref flags &= ~value
}

// Replaces a flag set with value.
#[Inline]
func(T) set(flags: *T, value: T)
    where Reflection.isEnum(T)
{
    dref flags = value
}

// Toggles value in a flag set.
#[Inline]
func(T) toggle(flags: *T, value: T)
    where Reflection.isEnum(T)
{
    dref flags ^= value
}
