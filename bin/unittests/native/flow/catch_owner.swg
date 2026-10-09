#global private

var catchOwnerDrops:        [256] Swag.AtomicValue'u32
var catchOwnerFailDefers:   u32
var catchOwnerNoFailDefers: u32
var catchOwnerHandlerRuns:  u32

struct CatchOwnerError
{
    generation: u32
}

impl CatchOwnerError
{
    mtd opPostCopy() { .generation += 1 }
    mtd opDrop() { catchOwnerDrops[.generation].add(1) }
}

func failCatchOwner(generation: u32) fail
{
    fail CatchOwnerError{generation: generation}
}

func catchOwnerEarlyReturn()->u32
{
    defer #fail catchOwnerFailDefers += 1
    defer #nofail catchOwnerNoFailDefers += 1
    catch failCatchOwner(48) else do
        return 1
    return 0
}

func rethrowCatchOwner() fail
{
    catch failCatchOwner(80) as error
    if error != null do
        fail error
}

#[Swag.Inline]
func inlineCatchOwner()->u32
{
    catch failCatchOwner(112) as error
    if error != null do
        return assume cast(const *CatchOwnerError, error).generation
    return 0
}

func catchOwnerSucceeds() fail {}

func catchOwnerBoolean()->bool fail
{
    try failCatchOwner(128)
    return true
}

#[Swag.NoInline]
func conditionalCatchOwner(take: bool)
{
    let result = take and (catch catchOwnerBoolean() as error)
    Swag.assert(not result)
    Swag.assert((error != null) == take)
}

#[Swag.NoInline]
func deferredDirectCatchOwner()
{
    defer catch failCatchOwner(176)
    return
}

#[Swag.NoInline]
func deferredHandledCatchOwner()
{
    defer #nofail catchOwnerNoFailDefers += 1
    defer catch failCatchOwner(192) else
    {
        catchOwnerHandlerRuns += 1
    }
    return
}

// Count destruction without dereferencing a payload after it might have been released.
#test
{
    for &drops in catchOwnerDrops do
        drops.store(0)
    catchOwnerFailDefers   = 0
    catchOwnerNoFailDefers = 0

    var firstGeneration  = 0'u32
    var secondGeneration = 0'u32
    {
        catch failCatchOwner(0) as first
        Swag.assert(first != null and (first is CatchOwnerError))
        firstGeneration = assume cast(const *CatchOwnerError, first).generation
        Swag.assert(firstGeneration < 16)
        Swag.assert(catchOwnerDrops[firstGeneration].load() == 0)

        catch failCatchOwner(16) as second
        Swag.assert(second != null and (second is CatchOwnerError))
        secondGeneration = assume cast(const *CatchOwnerError, second).generation
        Swag.assert(secondGeneration == 16 + firstGeneration)
        Swag.assert(catchOwnerDrops[firstGeneration].load() == 0)
        Swag.assert(catchOwnerDrops[secondGeneration].load() == 0)
    }
    Swag.assert(catchOwnerDrops[firstGeneration].load() == 1)
    Swag.assert(catchOwnerDrops[secondGeneration].load() == 1)

    // An uncaptured final error is released without waiting for another failure.
    catch failCatchOwner(32)
    Swag.assert(catchOwnerDrops[32 + firstGeneration].load() == 1)

    // A handler return runs its cleanup before the enclosing function's conditional defers.
    let returned = catchOwnerEarlyReturn()
    Swag.assert(returned == 1)
    Swag.assert(catchOwnerDrops[48 + firstGeneration].load() == 1)
    Swag.assert(catchOwnerFailDefers == 0 and catchOwnerNoFailDefers == 1)
    Swag.assert(Swag.getContext().curError == null and Swag.getContext().hasError == 0)

    // Each iteration owns one capture, even though the stack slot is reused.
    for 3
    {
        catch failCatchOwner(64) as error
        Swag.assert(error != null)
    }
    Swag.assert(catchOwnerDrops[64 + firstGeneration].load() == 3)

    var rethrownGeneration = 0'u32
    {
        catch rethrowCatchOwner() as error
        Swag.assert(error != null and (error is CatchOwnerError))
        rethrownGeneration = assume cast(const *CatchOwnerError, error).generation
        Swag.assert(rethrownGeneration >= 80 and rethrownGeneration < 96)
        Swag.assert(catchOwnerDrops[rethrownGeneration].load() == 0)
    }
    Swag.assert(catchOwnerDrops[rethrownGeneration].load() == 1)

    for 3
    {
        catch failCatchOwner(96) else do
            break
    }
    Swag.assert(catchOwnerDrops[96 + firstGeneration].load() == 1)
    Swag.assert(Swag.getContext().curError == null and Swag.getContext().hasError == 0)

    let inlineGeneration = inlineCatchOwner()
    Swag.assert(inlineGeneration >= 112 and inlineGeneration < 128)
    Swag.assert(catchOwnerDrops[inlineGeneration].load() == 1)

    // The enclosing cleanup is safe even when short-circuiting skips the catch entirely.
    conditionalCatchOwner(false)
    conditionalCatchOwner(true)
    conditionalCatchOwner(false)
    Swag.assert(catchOwnerDrops[128 + firstGeneration].load() == 1)

    // A successful nested catch leaves its capture null while the outer handler owns an error.
    catch failCatchOwner(144) else
    {
        catch catchOwnerSucceeds() as success
        Swag.assert(success == null)
        Swag.assert(catchOwnerDrops[144 + firstGeneration].load() == 0)
    }
    Swag.assert(catchOwnerDrops[144 + firstGeneration].load() == 1)
    Swag.assert(Swag.getContext().curError == null and Swag.getContext().hasError == 0)

    {
        defer
        {
            catch failCatchOwner(160) as cleanupError
            Swag.assert(cleanupError != null)
            Swag.assert(catchOwnerDrops[160 + firstGeneration].load() == 0)
        }
    }
    Swag.assert(catchOwnerDrops[160 + firstGeneration].load() == 1)

    // Explicit returns unwind through a live deferred-action cursor. Captures created inside
    // that action still leave first, including when its handler runs. A handler cannot return
    // or raise from the deferred body: control flow cannot leave a 'defer'.
    let previousOwners = Swag.getContext().errorCaptures
    deferredDirectCatchOwner()
    Swag.assert(Swag.getContext().errorCaptures == previousOwners)
    Swag.assert(catchOwnerDrops[176 + firstGeneration].load() == 1)

    let previousNoFail  = catchOwnerNoFailDefers
    let previousHandler = catchOwnerHandlerRuns
    deferredHandledCatchOwner()
    Swag.assert(Swag.getContext().errorCaptures == previousOwners)
    Swag.assert(catchOwnerDrops[192 + firstGeneration].load() == 1)
    Swag.assert(catchOwnerNoFailDefers == previousNoFail + 1)
    Swag.assert(catchOwnerHandlerRuns == previousHandler + 1)
}
