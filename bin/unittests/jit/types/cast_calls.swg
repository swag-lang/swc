#global private

#[Swag.DynCast]
struct CastCallBase { number: s32 = 19 }

struct CastCallChild
{
    prefix:     u64 = 7
    using base: CastCallBase
    extra:      s32 = 42
}

interface ICastCall
{
    mtd value()->s32
}

impl ICastCall for CastCallChild
{
    mtd value()->s32 => .extra
}

#[Swag.Safety(.Assume, false), Swag.Safety(.DynCast, false), Swag.Safety(.Null, false)]
func checkedCastCall(value: *CastCallBase?)->s32 fail
{
    let child = try cast(*CastCallChild, value)
    return child.extra
}

#[Swag.Safety(.Assume, false), Swag.Safety(.DynCast, true), Swag.Safety(.Null, true)]
func assumedCastCall(value: *CastCallBase?)->*CastCallChild
{
    return assume cast(*CastCallChild, value)
}

func fallibleBase(value: *CastCallBase?)->*CastCallBase? fail
{
    if value == null do fail Swag.BaseError{"missing base"}
    return value
}

#[Swag.Safety(.Assume, false)]
func assumedCastFromCall(value: *CastCallBase?)->*CastCallChild
{
    return assume (cast(*CastCallChild, fallibleBase(value)))
}

#[Swag.Safety(.Null, false)]
func checkedPresence(value: *s32?)->s32 fail
{
    return (try cast(*s32, value))[]
}

#test
{
    var child: CastCallChild
    let base:  *CastCallBase = &child
    Swag.assert(base == &child.base)
    Swag.assert(assumedCastCall(base) == &child)
    Swag.assert(assumedCastFromCall(base) == &child)
    Swag.assert(expect checkedCastCall(base) == 42)
    Swag.assert((expect cast(*CastCallChild, base)).extra == 42)
    Swag.assert(cast(ICastCall, &child).value() == 42)
    let inferred: s64 = cast(10 + 2)
    Swag.assert(inferred == 12)
    Swag.assert(cast(u64, cast(s64, 9) + 1) == 10)
}

#test
{
    var base: CastCallBase
    let mismatch = catch checkedCastCall(&base) as mismatchError
    Swag.assert(mismatch == 0 and mismatchError != null)
    let absent = catch checkedCastCall(null) as nullError
    Swag.assert(absent == 0 and nullError != null)
    var number: s32 = 27
    Swag.assert(expect checkedPresence(&number) == 27)
    let absentNumber = catch checkedPresence(null) as presenceError
    Swag.assert(absentNumber == 0 and presenceError != null)
}

#test
{
    var child: CastCallChild
    let view = cast(ICastCall, &child)
    Swag.assert((expect cast(*CastCallChild, view)) == &child)
    var number: s32 = 37
    let boxed:  any = number
    Swag.assert(expect cast(s32, boxed) == 37)
    let wrong = catch cast(*CastCallChild?, boxed) as error
    Swag.assert(wrong == null and error != null)
}
#[Swag.Safety(.Assume, false), Swag.Safety(.DynCast, false), Swag.Safety(.Null, false)]
func checkedBoxedString(value: any)->u64 fail
{
    return (try cast(string, value)).count
}

func nullableStaticInterface(value: *CastCallChild?)->ICastCall?
{
    return cast(ICastCall?, value)
}

#test
{
    let missing: string? = null
    let boxed:   any     = missing
    let length           = catch checkedBoxedString(boxed) as error
    Swag.assert(length == 0 and error != null)
    Swag.assert(nullableStaticInterface(null) == null)
    var child: CastCallChild
    let view = nullableStaticInterface(&child)
    Swag.assert(view != null and view.value() == 42)
}
#[Swag.Safety(.Assume, false), Swag.Safety(.DynCast, false), Swag.Safety(.Null, false)]
func checkedInterfacePresence(value: ICastCall?)->s32 fail
{
    return (try cast(ICastCall, value)).value()
}

#test
{
    let absent = catch checkedInterfacePresence(null) as error
    Swag.assert(absent == 0 and error != null)
    var child: CastCallChild
    Swag.assert(expect checkedInterfacePresence(cast(ICastCall, &child)) == 42)
}
