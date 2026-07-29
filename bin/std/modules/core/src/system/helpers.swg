#global public

using Swag

// Enum
//////////////////////////////////////////////

// Performs the has operation.
#[Inline]
func(T) has(flags, value: T)->bool
    where Reflection.isEnumFlags(T)
{
    return flags & value != 0
}

// Performs the equals operation.
#[Inline]
func(T) equals(flags, value: T)->bool
    where Reflection.isEnumFlags(T)
{
    return flags == value
}

// Performs the add operation.
#[Inline]
func(T) add(flags: &T, value: T)
    where Reflection.isEnumFlags(T)
{
    flags |= value
}

// Performs the remove operation.
#[Inline]
func(T) remove(flags: &T, value: T)
    where Reflection.isEnumFlags(T)
{
    flags &= ~value
}

// Performs the set operation.
#[Inline]
func(T) set(flags: &T, value: T)
    where Reflection.isEnumFlags(T)
{
    flags = value
}

// Performs the toggle operation.
#[Inline]
func(T) toggle(flags: &T, value: T)
    where Reflection.isEnumFlags(T)
{
    flags ^= value
}
