#global private

struct CleanupError
{
    using base: Swag.BaseError
    code:       s32
}

#[Swag.NoInline]
func cleanup() fail
{
    fail CleanupError{code: 7}
}

#[Swag.NoInline]
func readValue(shouldFail: bool)->s32 fail
{
    if shouldFail do
        fail CleanupError{code: 9}
    return 42
}

#[Swag.NoInline]
func readWithCleanup(shouldFail: bool)->s32 fail
{
    defer discard catch cleanup()
    let value = try readValue(shouldFail)
    return value
}

#[Swag.NoInline]
func readWithBoundCleanup(shouldFail: bool)->s32 fail
{
    defer
    {
        catch cleanup() as err
        Swag.assert(err != null)
        Swag.assert((cast(CleanupError) err).code == 7)
    }
    let value = try readValue(shouldFail)
    return value
}

#test
{
    let value = catch readWithCleanup(false) as err
    Swag.assert(err == null)
    Swag.assert(value == 42)
}

#test
{
    discard catch readWithCleanup(true) as err
    Swag.assert(err != null)
    Swag.assert((cast(CleanupError) err).code == 9)
}

#test
{
    let value = catch readWithBoundCleanup(false) as err
    Swag.assert(err == null)
    Swag.assert(value == 42)
}

#test
{
    discard catch readWithBoundCleanup(true) as err
    Swag.assert(err != null)
    Swag.assert((cast(CleanupError) err).code == 9)
}
