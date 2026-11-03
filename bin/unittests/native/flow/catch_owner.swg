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
    catch failCatchOwner(48) do
        return 1
    return 0
}

func rethrowCatchOwner() fail
{
    catch failCatchOwner(80) { fail Swag.err }
}

#[Swag.Inline]
func inlineCatchOwner()->u32
{
    catch failCatchOwner(112) { return assume cast(const *CatchOwnerError, Swag.err).generation }
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
    var errorOutcome: Swag.Error
    let result = take and (catch catchOwnerBoolean() as errorOutcome)
    let error  = errorOutcome.value()
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
    defer catch failCatchOwner(192)
    {
        catchOwnerHandlerRuns += 1
    }
    return
}

#[Swag.NoInline]
func deferredFailingCatchOwner() fail
{
    defer catch failCatchOwner(208)
    {
        fail CatchOwnerError{generation: 224}
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
    scope
    {
        var firstOutcome: Swag.Error
        catch failCatchOwner(0) as firstOutcome
        let first = firstOutcome.value()
        Swag.require(first != null and (first is CatchOwnerError))
        firstGeneration = assume cast(const *CatchOwnerError, first).generation
        Swag.require(firstGeneration < 16)
        Swag.require(catchOwnerDrops[firstGeneration].load() == 0)

        var secondOutcome: Swag.Error
        catch failCatchOwner(16) as secondOutcome
        let second = secondOutcome.value()
        Swag.require(second != null and (second is CatchOwnerError))
        secondGeneration = assume cast(const *CatchOwnerError, second).generation
        Swag.require(secondGeneration == 16 + firstGeneration)
        Swag.require(catchOwnerDrops[firstGeneration].load() == 0)
        Swag.require(catchOwnerDrops[secondGeneration].load() == 0)
    }
    Swag.require(catchOwnerDrops[firstGeneration].load() == 1)
    Swag.require(catchOwnerDrops[secondGeneration].load() == 1)

    // An uncaptured final error is released without waiting for another failure.
    catch failCatchOwner(32)
    Swag.require(catchOwnerDrops[32 + firstGeneration].load() == 1)

    // A handler return runs its cleanup before the enclosing function's conditional defers.
    let returned = catchOwnerEarlyReturn()
    Swag.require(returned == 1)
    Swag.require(catchOwnerDrops[48 + firstGeneration].load() == 1)
    Swag.require(catchOwnerFailDefers == 0 and catchOwnerNoFailDefers == 1)
    Swag.require(Swag.getContext().curError == null and Swag.getContext().hasError == 0)

    // Each iteration owns one capture, even though the stack slot is reused.
    for 3
    {
        var errorOutcome: Swag.Error
        catch failCatchOwner(64) as errorOutcome
        let error = errorOutcome.value()
        Swag.require(error != null)
    }
    Swag.require(catchOwnerDrops[64 + firstGeneration].load() == 3)

    var rethrownGeneration = 0'u32
    scope
    {
        var errorOutcome: Swag.Error
        catch rethrowCatchOwner() as errorOutcome
        let error = errorOutcome.value()
        Swag.require(error != null and (error is CatchOwnerError))
        rethrownGeneration = assume cast(const *CatchOwnerError, error).generation
        Swag.require(rethrownGeneration >= 80 and rethrownGeneration < 96)
        Swag.require(catchOwnerDrops[rethrownGeneration].load() == 0)
    }
    Swag.require(catchOwnerDrops[rethrownGeneration].load() == 1)

    for 3
    {
        catch failCatchOwner(96) do
            break
    }
    Swag.require(catchOwnerDrops[96 + firstGeneration].load() == 1)
    Swag.require(Swag.getContext().curError == null and Swag.getContext().hasError == 0)

    let inlineGeneration = inlineCatchOwner()
    Swag.require(inlineGeneration >= 112 and inlineGeneration < 128)
    Swag.require(catchOwnerDrops[inlineGeneration].load() == 1)

    // The enclosing cleanup is safe even when short-circuiting skips the catch entirely.
    conditionalCatchOwner(false)
    conditionalCatchOwner(true)
    conditionalCatchOwner(false)
    Swag.require(catchOwnerDrops[128 + firstGeneration].load() == 1)

    // A successful nested catch leaves its capture null while the outer handler owns an error.
    catch failCatchOwner(144)
    {
        var successOutcome: Swag.Error
        catch catchOwnerSucceeds() as successOutcome
        let success = successOutcome.value()
        Swag.require(success == null)
        Swag.require(catchOwnerDrops[144 + firstGeneration].load() == 0)
    }
    Swag.require(catchOwnerDrops[144 + firstGeneration].load() == 1)
    Swag.require(Swag.getContext().curError == null and Swag.getContext().hasError == 0)

    scope
    {
        defer
        {
            var cleanupErrorOutcome: Swag.Error
            catch failCatchOwner(160) as cleanupErrorOutcome
            let cleanupError = cleanupErrorOutcome.value()
            Swag.require(cleanupError != null)
            Swag.require(catchOwnerDrops[160 + firstGeneration].load() == 0)
        }
    }
    Swag.require(catchOwnerDrops[160 + firstGeneration].load() == 1)

    // Explicit returns unwind through a live deferred-action cursor. Captures created inside
    // that action still leave first, including when its handler runs or raises a new error. A
    // handler cannot return from the deferred body: control flow cannot leave a 'defer'.
    let previousOwners = Swag.getContext().errorCaptures
    deferredDirectCatchOwner()
    Swag.require(Swag.getContext().errorCaptures == previousOwners)
    Swag.require(catchOwnerDrops[176 + firstGeneration].load() == 1)

    let previousNoFail  = catchOwnerNoFailDefers
    let previousHandler = catchOwnerHandlerRuns
    deferredHandledCatchOwner()
    Swag.require(Swag.getContext().errorCaptures == previousOwners)
    Swag.require(catchOwnerDrops[192 + firstGeneration].load() == 1)
    Swag.require(catchOwnerNoFailDefers == previousNoFail + 1)
    Swag.require(catchOwnerHandlerRuns == previousHandler + 1)

    catch deferredFailingCatchOwner()
    Swag.require(Swag.getContext().errorCaptures == previousOwners)
    Swag.require(catchOwnerDrops[208 + firstGeneration].load() == 1)
    Swag.require(catchOwnerDrops[224 + firstGeneration].load() == 1)
}
