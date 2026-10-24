#global private

var copies, drops: u32
struct Owner { value, padding1, padding2: u64 }
impl Owner
{
    mtd opPostCopy() { copies += 1 }
    mtd opDrop() { if .value != 0 do drops += 1 }
}

#[Swag.NoInline]
func take(value: #move Owner)->u64
{
    let owned = #move value
    Swag.assert(#typeof(owned) == Owner)
    return owned.value
}

#[Swag.Inline]
func takeParenthesized(value: #move Owner)->u64
{
    var owned = (#move value)
    Swag.assert(#typeof(owned) == Owner)
    owned.value += 1
    return owned.value
}

#[Swag.NoInline]
func copyParameter(value: #move Owner)->u64
{
    let owned = value
    Swag.assert(#typeof(owned) == Owner)
    return owned.value
}

#test
{
    copies, drops = 0
    var first: Owner = {value: 17}
    Swag.assert(take(#move first) == 17 and first.value == 0)
    Swag.assert(copies == 0 and drops == 1)
    var second: Owner = {value: 23}
    Swag.assert(takeParenthesized(#move second) == 24 and second.value == 0)
    Swag.assert(copies == 0 and drops == 2)
}

#test
{
    copies, drops = 0
    var value: Owner = {value: 29}
    Swag.assert(copyParameter(#move value) == 29)
    Swag.assert(value.value == 29 and copies == 1 and drops == 1)
}

#[Swag.NoCopy]
struct MoveOnly { value, padding1, padding2: u64 }
impl MoveOnly { mtd opDrop() {} }

#[Swag.NoInline]
func takeMoveOnly(value: #move MoveOnly)->u64
{
    let owned = #move value
    return owned.value
}

#[Swag.NoInline]
func takeMoveOnlyParenthesized(value: #move MoveOnly)->u64
{
    let owned = (#move value)
    return owned.value
}

#test
{
    var first  = MoveOnly{31}
    var second = MoveOnly{37}
    Swag.assert(takeMoveOnly(#move first) == 31 and first.value == 0)
    Swag.assert(takeMoveOnlyParenthesized(#move second) == 37 and second.value == 0)
}

#test
{
    copies, drops = 0
    scope
    {
        var source       = Owner{41}
        let owned: Owner = (#move source)
        Swag.assert(owned.value == 41 and source.value == 0 and copies == 0)
    }
    Swag.assert(drops == 1)
}
