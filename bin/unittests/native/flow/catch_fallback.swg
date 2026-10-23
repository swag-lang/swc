#global private

// 'catch e else V' yields V when 'e' fails. V is evaluated on the failure path only, after an
// 'as err' capture is bound, and it converts to the operand's result type. It needs no implicit
// default, so results that have none can be caught too.

struct FallbackError
{
    using base: Swag.BaseError
    code:       s32 = 0
}

struct FallbackPoint
{
    x: s32 = 5
    y: s32 = 7
}

struct FallbackItem
{
    value: s32
}

var g_fallbackItem  = FallbackItem{value: 3}
var g_fallbackOther = FallbackItem{value: 9}
var g_fallbackEvals = 0

func fallbackCount(ok: bool)->s32 fail
{
    if not ok do
        fail FallbackError{base: Swag.BaseError{"no count"}, code: 11}
    return 4
}

func fallbackPoint(ok: bool)->FallbackPoint fail
{
    if not ok do
        fail FallbackError{base: Swag.BaseError{"no point"}, code: 12}
    return {x: 1, y: 2}
}

func fallbackItem(ok: bool)->*FallbackItem fail
{
    if not ok do
        fail FallbackError{base: Swag.BaseError{"no item"}, code: 13}
    return &g_fallbackItem
}

func fallbackTuple(ok: bool)->{value: s32, valid: bool} fail
{
    if not ok do
        fail FallbackError{base: Swag.BaseError{"no tuple"}, code: 14}
    return {8, true}
}

func fallbackValue(value: s32)->s32
{
    g_fallbackEvals += 1
    return value
}

func fallbackCode(err: any?)->s32 => err == null ? 0 : assume cast(FallbackError, err).code

#test
{
    g_fallbackEvals = 0
    Swag.assert((catch fallbackCount(true) else fallbackValue(-1)) == 4)
    Swag.assert(g_fallbackEvals == 0)
    Swag.assert((catch fallbackCount(false) else fallbackValue(-1)) == -1)
    Swag.assert(g_fallbackEvals == 1)
}

// The fallback reads the capture bound by the same handler.
#test
{
    let value = catch fallbackCount(false) as err else fallbackCode(err)
    Swag.assert(value == 11)

    let other = catch fallbackCount(true) as otherErr else fallbackCode(otherErr)
    Swag.assert(other == 4)
}

// An aggregate fallback is the one written, not zeroed storage.
#test
{
    let point = catch fallbackPoint(false) else {}
    Swag.assert(point.x == 5 and point.y == 7)

    let explicit = catch fallbackPoint(false) else {x: -1, y: -2}
    Swag.assert(explicit.x == -1 and explicit.y == -2)

    let success = catch fallbackPoint(true) else {}
    Swag.assert(success.x == 1 and success.y == 2)

    let pair = catch fallbackTuple(false) else {-1, false}
    Swag.assert(pair.value == -1 and not pair.valid)
}

// A non-null pointer has no default; 'else' supplies the replacement.
#test
{
    let item = catch fallbackItem(false) else &g_fallbackOther
    Swag.assert(item.value == 9)

    let found = catch fallbackItem(true) else &g_fallbackOther
    Swag.assert(found.value == 3)
}

// A fallback may handle its own failure.
#test
{
    let value = catch fallbackCount(false) else catch fallbackCount(false) else 21
    Swag.assert(value == 21)
}

func(T) fallbackProduce(ok: bool, value: T)->T fail
{
    if not ok do
        fail FallbackError{base: Swag.BaseError{"no value"}, code: 15}
    return value
}

func(T) fallbackGeneric(ok: bool, value: T, fallback: T)->T => catch fallbackProduce(ok, value) else fallback

#test
{
    Swag.assert(fallbackGeneric(true, 1, 2) == 1)
    Swag.assert(fallbackGeneric(false, 1, 2) == 2)
    Swag.assert(fallbackGeneric(false, 1.5, 2.5) == 2.5)
}

var g_fallbackDrops = 0

struct FallbackOwned
{
    id: s32
}

impl FallbackOwned
{
    mtd opDrop() { g_fallbackDrops += 1 }
}

func fallbackOwned(ok: bool)->FallbackOwned fail
{
    if not ok do
        fail FallbackError{base: Swag.BaseError{"no owned"}, code: 16}
    return {id: 1}
}

// A temporary fallback is adopted by the result; a named one is copied, and both are dropped.
#test
{
    g_fallbackDrops = 0
    {
        let owned = catch fallbackOwned(false) else FallbackOwned{id: 2}
        Swag.assert(owned.id == 2)
    }

    Swag.assert(g_fallbackDrops == 1)

    g_fallbackDrops = 0
    {
        let named = FallbackOwned{id: 3}
        let owned = catch fallbackOwned(false) else named
        Swag.assert(owned.id == 3)
    }

    Swag.assert(g_fallbackDrops == 2)
}
