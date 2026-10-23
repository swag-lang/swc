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
        var errOutcome: Swag.Error
        catch cleanup() as &errOutcome
        let err = errOutcome.value()
        Swag.assert(err != null)
        Swag.assert(assume cast(CleanupError, err).code == 7)
    }
    let value = try readValue(shouldFail)
    return value
}

#test
{
    var errOutcome: Swag.Error
    var value:      #decltype(expect readWithCleanup(false))
    catch { value = try readWithCleanup(false) } as &errOutcome
    let err = errOutcome.value()
    Swag.assert(err == null)
    Swag.assert(value == 42)
}

#test
{
    var errOutcome: Swag.Error
    discard catch readWithCleanup(true) as &errOutcome
    let err = errOutcome.value()
    Swag.assert(err != null)
    Swag.assert(assume cast(CleanupError, err).code == 9)
}

#test
{
    var errOutcome: Swag.Error
    var value:      #decltype(expect readWithBoundCleanup(false))
    catch { value = try readWithBoundCleanup(false) } as &errOutcome
    let err = errOutcome.value()
    Swag.assert(err == null)
    Swag.assert(value == 42)
}

#test
{
    var errOutcome: Swag.Error
    discard catch readWithBoundCleanup(true) as &errOutcome
    let err = errOutcome.value()
    Swag.assert(err != null)
    Swag.assert(assume cast(CleanupError, err).code == 9)
}
