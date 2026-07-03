#global private

enum OverA { A, B }
enum OverB { A, B }

#[Swag.Strict]
alias StrictOverB = OverB

func overload(x: s32, e: OverA)->s32 { return 10 }
func overload(x: f32, e: OverB)->f32 { return 20.0 }
func overloadStrictAlias(x: s32, e: OverA)->s32 { return 30 }
func overloadStrictAlias(x: f32, e: StrictOverB)->f32 { return 40.0 }
func strictAliasEnumArg(e: StrictOverB)->s32
{
    if e == cast(StrictOverB) OverB.A do
        return 1
    return 2
}

// Overload resolution via auto-scope enum arg
#test
{
    let r = overload(1.0, .A)
    #assert(#typeof(r) == f32)
    @assert(r == 20.0)
}

func fct(x: f32, e: OverB)->f32 { return 20.0 }

struct Vec2
{
    x: f32
    y: f32
}

impl Vec2
{
    func set_axis(axis: OverA, value: f32)
    {
        if axis == .A {
        } elif axis == .B {
        }
    }

    mtd toto()
    {
    }

    func titi()->Vec2
    {
        set_axis(.A, 1.0)
        return {}
    }
}

// Explicit enum qualification in overload call
#test
{
    let r2 = overload(1's32, OverA.A)
    #assert(#typeof(r2) == s32)
    @assert(r2 == 10)
}

// Auto-scope enum in non-overloaded call
#test
{
    let r3 = fct(1.0, .A)
    #assert(#typeof(r3) == f32)
    @assert(r3 == 20.0)
}

#test
{
    @assert(strictAliasEnumArg(.A) == 1)
    @assert(strictAliasEnumArg(.B) == 2)

    let r4 = overloadStrictAlias(1.0, .A)
    #assert(#typeof(r4) == f32)
    @assert(r4 == 40.0)
}

#[Swag.EnumFlags]
enum ConflictingFlagName
{
    Name
    Other
}

func(T) has(flags, value: T)->bool
{
    return flags & value != 0
}

func(T) add(flags: &T, value: T)
{
    flags |= value
}

struct ConflictingFlagOwner
{
}

impl ConflictingFlagOwner
{
    attr Name(text: string)

    mtd checkFlags()
    {
        var flags = ConflictingFlagName.Name
        flags.add(.Other)
        @assert(flags.has(.Name))
        @assert(flags.has(.Other))
    }
}

#test
{
    var owner: ConflictingFlagOwner
    owner.checkFlags()
}
