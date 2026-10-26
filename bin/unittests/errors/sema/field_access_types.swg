#global internal

// Types used by 'sema_err_field_private' and 'sema_err_field_readonly'. Member access is
// judged against the file that declares the aggregate, so the violations must be written
// from another file.

struct AccessSafe
{
    private key: s32 = 5
}

impl AccessSafe
{
    mtd read()->s32 => .key
}

// A method of a 'private impl' belongs to the type, as a private field does. 'pick' is an
// overload set that mixes both levels, so another file reaches the internal overload only.
private impl AccessSafe
{
    mtd secret()->s32      => .key
    mtd pick(_: bool)->s32 => 0
}

impl AccessSafe
{
    mtd pick(_: s32)->s32 => .secret()
}

struct AccessCounter
{
    public readonly count: s32
}

impl AccessCounter
{
    mtd bump() { .count += 1 }
}

// 'readonly' written alone rides on the default level, so this one reads inside the module and
// is still written by its own type only.
struct AccessInternalCounter
{
    readonly count: s32
}

impl AccessInternalCounter
{
    mtd bump() { .count += 1 }
}

// Embedding the owner grants nothing: the embedder is not the declaring type, and this file
// is not the one that declares 'AccessSafe'.
struct AccessHost
{
    using base: AccessSafe
}
