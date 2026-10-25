#global private

// 'return #move place' gives away a place that outlives the return -- a field, a pointee -- so
// the place is reset and the value has one owner: one move, no copy, one drop in the end.

var PlaceCopies: s32
var PlaceMoves:  s32
var PlaceDrops:  s32

func resetPlaceCounters()
{
    PlaceCopies, PlaceMoves, PlaceDrops = 0
}

// Wider than a register, so it returns through caller storage and runs its hooks.
struct WidePlace
{
    data:  [16] u8
    value: s32
}

impl WidePlace
{
    mtd opPostCopy() { PlaceCopies += 1 }
    mtd opPostMove() { PlaceMoves += 1 }

    mtd opDrop()
    {
        if .value != 0 do
            PlaceDrops += 1
    }
}

// Fits a register, so it returns by value and runs no hook.
struct NarrowPlace
{
    value: s32
}

impl NarrowPlace
{
    mtd opDrop()
    {
        if .value != 0 do
            PlaceDrops += 1
    }
}

struct PlaceHolder
{
    wide:   WidePlace
    narrow: NarrowPlace
}

impl PlaceHolder
{
    mtd takeWide()->WidePlace
    {
        return #move .wide
    }

    mtd takeWideExpression()->WidePlace => #move .wide

    mtd takeNarrow()->NarrowPlace
    {
        return #move .narrow
    }

    #[Swag.Inline]
    mtd takeWideInline()->WidePlace
    {
        return #move .wide
    }
}

func takePointee(source: *WidePlace)->WidePlace
{
    return #move source[]
}

#test
{
    resetPlaceCounters()
    scope
    {
        var holder = PlaceHolder{wide: WidePlace{value: 5}}
        let taken  = holder.takeWide()
        Swag.assert(taken.value == 5 and holder.wide.value == 0)
        Swag.assert(PlaceCopies == 0 and PlaceMoves == 1)
    }

    Swag.assert(PlaceDrops == 1)
}

#test
{
    resetPlaceCounters()
    scope
    {
        var holder = PlaceHolder{wide: WidePlace{value: 6}}
        let taken  = holder.takeWideExpression()
        Swag.assert(taken.value == 6 and holder.wide.value == 0)
        Swag.assert(PlaceCopies == 0)
    }

    Swag.assert(PlaceDrops == 1)
}

#test
{
    resetPlaceCounters()
    scope
    {
        var holder = PlaceHolder{narrow: NarrowPlace{value: 7}}
        let taken  = holder.takeNarrow()
        Swag.assert(taken.value == 7 and holder.narrow.value == 0)
    }

    Swag.assert(PlaceDrops == 1)
}

#test
{
    resetPlaceCounters()
    scope
    {
        var holder = PlaceHolder{wide: WidePlace{value: 8}}
        let taken  = holder.takeWideInline()
        Swag.assert(taken.value == 8 and holder.wide.value == 0)
        Swag.assert(PlaceCopies == 0)
    }

    Swag.assert(PlaceDrops == 1)
}

#test
{
    resetPlaceCounters()
    scope
    {
        var source = WidePlace{value: 9}
        let taken  = takePointee(&source)
        Swag.assert(taken.value == 9 and source.value == 0)
        Swag.assert(PlaceCopies == 0)
    }

    Swag.assert(PlaceDrops == 1)
}

// 'retval' already is the return storage: moving it hands the value over untouched.
func buildInPlace(value: s32)->WidePlace
{
    var result: retval
    result.value = value
    return #move result
}

#test
{
    resetPlaceCounters()
    scope
    {
        let built = buildInPlace(10)
        Swag.assert(built.value == 10 and PlaceCopies == 0)
    }

    Swag.assert(PlaceDrops == 1)
}

#[Swag.Inline]
func buildInPlaceInline(value: s32)->WidePlace
{
    var result: retval
    result.value = value
    return #move result
}

#test
{
    resetPlaceCounters()
    scope
    {
        let built = buildInPlaceInline(11)
        Swag.assert(built.value == 11 and PlaceCopies == 0)
    }

    Swag.assert(PlaceDrops == 1)
}
