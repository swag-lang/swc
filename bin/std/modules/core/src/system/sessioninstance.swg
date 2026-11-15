#global public
#global namespace Env

// Owns an exclusive application presence for the current user and desktop session.
//
// Keep the value alive until the application finishes. The operating system releases the
// presence after a crash. Acquiring does not activate or communicate with the existing owner.
#[Swag.Opaque]
#[Swag.NoCopy]
struct SessionInstance
{
    internal handle: const [*] void?
}

impl SessionInstance
{
    // Acquires id, returning false when another live instance owns it.
    //
    // Id must contain 1–128 ASCII letters, digits, dots or hyphens. Fails for invalid input,
    // an already acquired owner or native resource errors. Serialize calls on the same owner.
    mtd acquire(id: string)->bool fail
    {
        if .handle or not validSessionApplicationId(id) do
            fail Errors.BadParameterError{}
        return try .acquireNative(id)
    }

    // Releases this presence. Repeated calls are safe; reacquisition is allowed.
    mtd close()
    {
        if .handle do
            .closeNative()
    }

    // Releases the application's presence when its owner leaves scope.
    mtd opDrop() { .close() }
}

internal func validSessionApplicationId(id: string)->bool
{
    if id.count == 0 or id.count > 128 do
        return false
    for byte in id
    {
        if not ((byte >= 'a' and byte <= 'z') or
                (byte >= 'A' and byte <= 'Z') or
                (byte >= '0' and byte <= '9') or
                byte == '.' or
                byte == '-') do
            return false
    }

    return true
}
