#global private

struct Holder { target: *u64? }

func storeThroughEncodedPointer(holder: *Holder)
{
    let bits  = cast(u64, holder)
    var local = 7'u64
    cast(*Holder, bits).target = &local     // swc-expected-error {{sanity_err_borrow_escape}}
}

// An immediate round trip still points into storage owned by this frame.
func localEncodedStorage()->u64
{
    var local   = 7'u64
    var holder: Holder
    let pointer = &holder
    cast(*Holder, cast(u64, pointer)).target = &local
    return holder.target![]
}

// Pointer qualifier conversions preserve ordinary field-sensitive tracking.
func localTypedStorage()->u64
{
    var local   = 11'u64
    var holder: Holder
    let pointer = &holder
    cast(*Holder, pointer).target = &local
    return holder.target![]
}
