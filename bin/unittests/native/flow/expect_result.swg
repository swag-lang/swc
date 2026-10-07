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
    Swag.assert(pointer[] == 42)
    let testTry = try requiredPointer()
    #assert(#typeof(testTry) == *s32)
    Swag.assert(testTry == pointer)
    Swag.assert(uncheckedExpectPointer()[] == 42)
    Swag.assert((expect absentSuccess()) == null)
}

#test
{
    drops = 0
    {
        let result = expect propagateResult(true)
        Swag.assert(result.pointer[] == 42)
        Swag.assert(result.payload[63] == 0)
    }
    Swag.assert(drops == 1)

    drops = 0
    catch consumeFailure() as error
    Swag.assert(error != null)
    Swag.assert(drops == 0, "an error produces no result to destroy")
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
    Swag.assert(drops == 1)
}
