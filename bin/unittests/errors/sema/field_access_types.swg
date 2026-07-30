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

struct AccessCounter
{
    readonly count: s32
}

impl AccessCounter
{
    mtd bump() { .count += 1 }
}

// Embedding the owner grants nothing: the embedder is not the declaring type, and this file
// is not the one that declares 'AccessSafe'.
struct AccessHost
{
    using base: AccessSafe
}
