#global private

var trace: u64
var failDuringDrop: bool

struct Owner
{
    value:   u64
    padding: [3] u64
}
impl Owner
{
    mtd opDrop()
    {
        if failDuringDrop do catch failCleanup()
        trace = trace * 10 + .value
    }
}

struct Result { value, second, third: u64 }

struct Failure
{
    using base: Swag.BaseError
    code:       u64
}

#[Swag.NoInline]
func makeOwner(value: u64)->Owner
{
    var result: retval
    result.value = value
    return result
}

#[Swag.NoInline]
func read(owner: Owner)->u64 => owner.value

#[Swag.NoInline]
func scalarResult()->u64
{
    defer trace = trace * 10 + 9
    return read(makeOwner(1))
}

#[Swag.NoInline]
func aggregateResult()->Result
{
    defer trace = trace * 10 + 9
    return {value: read(makeOwner(2))}
}

#[Swag.Inline]
func inlineResult()->u64
{
    defer trace = trace * 10 + 9
    return read(makeOwner(3))
}

#[Swag.NoInline]
func transferredResult()->Owner
{
    return makeOwner(read(makeOwner(4)))
}

#[Swag.NoInline]
func consume(owner: Owner) { discard owner }

#[Swag.NoInline]
func voidResult()
{
    defer trace = trace * 10 + 9
    return consume(makeOwner(5))
}

func failCleanup() fail { fail Failure{code: 1} }

#[Swag.NoInline]
func failureResult() fail
{
    fail Failure{code: read(makeOwner(6))}
}

// Return operands die before function-scope defers. The result is already captured.
#test
{
    trace = 0
    let result = scalarResult()
    Swag.assert(result == 1)
    Swag.assert(trace == 19)
}

#test
{
    trace = 0
    let result = aggregateResult()
    Swag.assert(result.value == 2)
    Swag.assert(trace == 29)
}

#test
{
    trace = 0
    let result = inlineResult()
    Swag.assert(result == 3)
    Swag.assert(trace == 39)
}

// Only the inner operand dies here; the returned owner belongs to the caller.
#test
{
    trace = 0
    {
        let result = transferredResult()
        Swag.assert(result.value == 4)
        Swag.assert(trace == 4)
    }
    Swag.assert(trace == 44)
}

#test
{
    trace = 0
    voidResult()
    Swag.assert(trace == 59)
}

#test
{
    trace = 0
    var errorOutcome: Swag.Error
    catch failureResult() as &errorOutcome
    let error = errorOutcome.value()
    if error do trace = trace * 10 + 9
    Swag.assert(trace == 69)
}

// Cleanup may handle its own failure without consuming the one being propagated.
#test
{
    trace = 0
    failDuringDrop = true
    var errorOutcome: Swag.Error
    catch failureResult() as &errorOutcome
    let error = errorOutcome.value()
    failDuringDrop = false
    Swag.assert(trace == 6)
    Swag.assert(error != null)
    if error is Failure as failure do Swag.assert(failure.code == 6)
    else do Swag.assert(false)
}
