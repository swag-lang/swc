#global private

// Struct fields defaulting to '= undefined' are skipped by the default
// initialization. Under 'Swag.Safety(.Lifecycle)' the skipped ranges are filled
// with the 0xDD poison on every construction path, so an unproven read fails
// deterministically; under 'Swag.Sanity(.Lifecycle)' the static check knows the
// ranges are undefined.

struct UndFieldItem
{
    ready: u32 = 7
    value: u32 = undefined
}

var g_undFieldSink: u32

// Address escape: silences the flow analysis and, through the call, the static
// backend check — only the poison remains.
func undFieldTouch(v: *UndFieldItem)
{
    g_undFieldSink += 1
    discard v
}

// The defaulted field is written, the undefined one holds the poison.
#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a: UndFieldItem
    undFieldTouch(&a)
    @assert(a.ready == 7)
    @assert(a.value == 0xDDDDDDDD)
}

// A written field reads back its store, poison overwritten.
#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a: UndFieldItem
    a.value = 11
    undFieldTouch(&a)
    @assert(a.ready == 7)
    @assert(a.value == 11)
}

// Literal construction also poisons the undefined field.
#[Swag.Safety(.Lifecycle, true)]
#test
{
    var a = UndFieldItem{ready: 9}
    undFieldTouch(&a)
    @assert(a.ready == 9)
    @assert(a.value == 0xDDDDDDDD)
}
