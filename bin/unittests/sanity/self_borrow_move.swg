#global private

struct SelfBorrowMove
{
    values: [4] s32
    cursor: *s32?
}

func readMovedSelfBorrow()->s32
{
    var source = SelfBorrowMove{}
    source.cursor = &source.values[0]
    var target = #move source
    return target.cursor![]     // swc-expected-error {{sanity_err_use_after_move}}
}

struct PackedSelfBorrowMove
{
    first, second: s32
    cursor:        *s32?
}

func readPackedMovedSelfBorrow()->s32
{
    var source = PackedSelfBorrowMove{}
    source.cursor = &source.first
    var target = #move source
    return target.cursor![]     // swc-expected-error {{sanity_err_use_after_move}}
}

struct FirstFieldSelfBorrowMove
{
    cursor: *s32?
    value:  s32
}

func readFirstFieldMovedSelfBorrow()->s32
{
    var source = FirstFieldSelfBorrowMove{}
    source.cursor = &source.value
    var target = #move source
    return target.cursor![]     // swc-expected-error {{sanity_err_use_after_move}}
}

#test
{
    discard readMovedSelfBorrow()
    discard readPackedMovedSelfBorrow()
    discard readFirstFieldMovedSelfBorrow()
}

// Copies keep borrowing live source storage. Replacing a copied pointer makes it
// independent of that source before the source is moved.
#test
{
    var source = SelfBorrowMove{}
    source.values[0] = 7
    source.cursor    = &source.values[0]
    var copied = source
    Swag.assert(copied.cursor![] == 7)

    var independent: s32 = 11
    copied.cursor = &independent
    var target = #move source
    Swag.assert(copied.cursor[] == 11)
    target.cursor = &target.values[0]
    Swag.assert(target.cursor[] == 7)
}

struct RepairedSelfBorrowMove
{
    value:  s32
    cursor: *s32?
}

impl RepairedSelfBorrowMove
{
    mtd opPostMove()
    {
        .cursor = &.value
    }
}

// A post-move hook can repair an internal pointer in its new storage.
#test
{
    var source = RepairedSelfBorrowMove{value: 13}
    source.cursor = &source.value
    var target = #move source
    Swag.assert(target.cursor![] == 13)
    target.cursor![] = 17
    Swag.assert(target.value == 17)
}
