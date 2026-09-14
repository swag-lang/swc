#global private

struct IndexedSelfBorrow
{
    value:    s32
    pointers: [2] (*s32?)
}

func readIndexedMovedBorrow()->s32
{
    var source = IndexedSelfBorrow{}
    source.pointers[1] = &source.value
    var target     = #move source
    var index: u64 = 1
    return target.pointers[index]![]     // swc-expected-error {{sanity_err_use_after_move}}
}

#test
{
    discard readIndexedMovedBorrow()
}

#test
{
    var source = IndexedSelfBorrow{}
    source.value       = 9
    source.pointers[1] = &source.value
    var target     = source
    var index: u64 = 1
    Swag.assert(target.pointers[index]![] == 9)
}
