#global private

struct Sliceable
{
    values: [4] s32
}

impl Sliceable
{
    mtd opSlice(low, up: u64)->const [..] s32
    {
        return me.values[low to up]
    }
}

// 'opSlice' takes an inclusive upper bound, so it cannot express an empty range.
#test
{
    var box: Sliceable
    discard box[2 until 2]     // swc-expected-error {{sema_err_range_empty_op_slice}}
}

#test
{
    var box: Sliceable
    discard box[0 until 0]     // swc-expected-error {{sema_err_range_empty_op_slice}}
}

// An inverted range keeps the general diagnostic.
#test
{
    var box: Sliceable
    discard box[2 until 1]     // swc-expected-error {{sema_err_range_invalid_bounds}}
}

// Non-empty ranges stay valid in both spellings.
#test
{
    var box: Sliceable
    discard box[1 until 3]
    discard box[1 to 2]
    discard box[2 to 2]
}
