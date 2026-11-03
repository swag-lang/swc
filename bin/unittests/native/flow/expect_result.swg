#global private

var storage: s32 = 42
var drops:   u32

struct RequiredResult
{
    pointer: *s32
    payload: [64] u64
}

impl RequiredResult
{
    mtd opDrop() { drops += 1 }
}

#[Swag.NoInline]
func requiredPointer()->*s32 fail => &storage

#[Swag.NoInline]
func requiredResult(succeed: bool)->RequiredResult fail
{
    if not succeed do fail Swag.BaseError{"no result"}
    return RequiredResult{pointer: &storage}
}

#[Swag.NoInline]
func propagateResult(succeed: bool)->RequiredResult fail => try requiredResult(succeed)

func consumeResult(value: RequiredResult) fail
{
    Swag.assert(value.pointer[] == 42)
}

func consumeFailure() fail
{
    try consumeResult(try propagateResult(false))
}

func absentSuccess()->*s32? fail => null

#[Swag.Safety(.All, false)]
func uncheckedExpectPointer()->*s32 => expect requiredPointer()

#test
{
    let pointer = expect requiredPointer()
    #assert(#typeof(pointer) == *s32)
    Swag.require(pointer[] == 42)
    Swag.require(uncheckedExpectPointer()[] == 42)
    Swag.require((expect absentSuccess()) == null)
}

#test
{
    drops = 0
    scope
    {
        let result = expect propagateResult(true)
        Swag.require(result.pointer[] == 42)
        Swag.require(result.payload[63] == 0)
    }
    Swag.require(drops == 1)

    drops = 0
    var errorOutcome: Swag.Error
    catch consumeFailure() as errorOutcome
    let error = errorOutcome.value()
    Swag.require(error != null)
    Swag.require(drops == 0, "an error produces no result to destroy")
}

func expectBlockResult()
{
    expect
    {
        let result = try propagateResult(true)
        Swag.assert(result.pointer[] == 42)
    }
}

#test
{
    drops = 0
    expectBlockResult()
    Swag.require(drops == 1)
}
