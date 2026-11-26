#global public

// Copies bytes through an inline body exported to another module.
#[Swag.Inline]
func depMemoryCopy(destination: [*] void, source: const [*] void, size: u64)
{
    if size
    {
        Swag.memcpy(destination, source, size)
    }
}

// Copies possibly overlapping bytes through an inline body exported to another module.
#[Swag.Inline]
func depMemoryMove(destination: [*] void, source: const [*] void, size: u64)
{
    if size
    {
        Swag.memmove(destination, source, size)
    }
}

// Clears bytes through an inline body exported to another module.
#[Swag.Inline]
func depMemoryClear(destination: [*] void, size: u64)
{
    if size
    {
        Swag.memset(destination, 0, size)
    }
}

// Fills bytes through an inline body exported to another module.
#[Swag.Inline]
func depMemorySet(destination: [*] void, value: u8, size: u64)
{
    if size
    {
        Swag.memset(destination, value, size)
    }
}

// Compares bytes through an inline body exported to another module.
#[Swag.Inline]
func depMemoryCompare(left: const [*] void, right: const [*] void, size: u64)->s32
{
    if not size
    {
        return 0
    }
    return Swag.memcmp(left, right, size)
}
