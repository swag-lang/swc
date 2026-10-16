#global private

struct MovedWriter
{
    values: [4] s32
    cursor: *s32?
}

func writeMovedBorrow()
{
    var source: MovedWriter
    source.cursor = &source.values[0]
    var target = #move source
    target.cursor![] = 7     // swc-expected-error {{sanity_err_write_after_move}}
}

struct PackedMovedWriter
{
    value:  s32
    cursor: *s32?
}

#[Swag.Safety(.ValueBorrow, false)]
func writePackedMovedBorrow()
{
    var source: PackedMovedWriter
    source.cursor = &source.value
    var target = #move source
    target.cursor![] = 9     // swc-expected-error {{sanity_err_write_after_move}}
}

func writeRelocatedBorrow()
{
    var source: PackedMovedWriter
    source.cursor = &source.value
    var target: PackedMovedWriter
    target = #relocate source
    target.cursor![] = 10     // swc-expected-error {{sanity_err_write_after_move}}
}

func readRelocatedBorrow()->s32
{
    var source: PackedMovedWriter
    source.cursor = &source.value
    var target: PackedMovedWriter
    target = #relocate source
    return target.cursor![]     // swc-expected-error {{sanity_err_use_after_move}}
}

struct FirstFieldMovedWriter
{
    cursor: *s32?
    value:  s32
}

func writeFirstFieldMovedBorrow()
{
    var source: FirstFieldMovedWriter
    source.cursor = &source.value
    var target = #move source
    target.cursor![] = 11     // swc-expected-error {{sanity_err_write_after_move}}
}

func writeEarlierPointer()
{
    var source: PackedMovedWriter
    let pointer = &source.value
    var target  = #move source
    discard target
    pointer[] = 13     // swc-expected-error {{sanity_err_write_after_move}}
}

struct IndexedMovedWriter
{
    values:   [4] s32
    pointers: [2] (*s32?)
}

func writeIndexedMovedBorrow()
{
    var source: IndexedMovedWriter
    source.pointers[1] = &source.values[0]
    var target     = #move source
    var index: u64 = 1
    target.pointers[index]![] = 15     // swc-expected-error {{sanity_err_write_after_move}}
}

#[Swag.NoInline]
func readAfterConditionalRefresh(refresh: bool)->s32
{
    var source: PackedMovedWriter
    var pointer = &source.value
    var target  = #move source
    discard target
    if refresh do pointer = &source.value
    return pointer[]     // swc-expected-error {{sanity_err_use_after_move}}
}

#test
{
    writeMovedBorrow()
    writePackedMovedBorrow()
    writeRelocatedBorrow()
    discard readRelocatedBorrow()
    writeFirstFieldMovedBorrow()
    writeEarlierPointer()
    writeIndexedMovedBorrow()
    discard readAfterConditionalRefresh(true)
}

// Direct stores reinitialize abandoned storage, including a field after a wide move.
#test
{
    var source: MovedWriter
    source.values[0] = 3
    var target = #move source
    source.values[0] = 17
    Swag.assert(source.values[0] == 17 and target.values[0] == 3)
}

// A fresh address can reinitialize that storage too; it is not a pre-move borrow.
#test
{
    var source: PackedMovedWriter
    var target = #move source
    let fresh  = &source.value
    fresh[] = 19
    Swag.assert(source.value == 19 and target.value == 0)
}

// Replacing an old pointer after the move creates the same fresh address.
#test
{
    var source: PackedMovedWriter
    var pointer = &source.value
    var target  = #move source
    pointer   = &source.value
    pointer[] = 23
    Swag.assert(source.value == 23 and target.value == 0)
}

// A proof cannot call this a stale write on every path: one path refreshes the pointer.
#[Swag.NoInline]
func conditionallyRefreshPointer(refresh: bool)->s32
{
    var source: PackedMovedWriter
    var pointer = &source.value
    var target  = #move source
    discard target
    if refresh do pointer = &source.value
    pointer[] = 27
    return source.value
}

#test { Swag.assert(conditionallyRefreshPointer(true) == 27) }

#[Swag.Inline]
func moveAndReset(source: *PackedMovedWriter)->PackedMovedWriter
{
    var target = #move source[]
    source[] = PackedMovedWriter{value: 47}
    return target
}

// Moving through an owning lvalue still permits replacing that same lvalue.
#test
{
    var source = PackedMovedWriter{value: 43}
    let target = moveAndReset(&source)
    Swag.assert(source.value == 47 and target.value == 43)
}

#test
{
    var source: MovedWriter
    source.cursor = &source.values[0]
    var target = #move source
    target.cursor   = &target.values[0]
    target.cursor[] = 29
    Swag.assert(target.values[0] == 29)
}

// A copy still borrows live source storage; an independent pointee survives a move.
#test
{
    var source: PackedMovedWriter
    source.cursor = &source.value
    var copied = source
    copied.cursor![] = 31
    Swag.assert(source.value == 31)

    var independent: s32
    source.cursor = &independent
    var target = #move source
    target.cursor![] = 37
    Swag.assert(independent == 37)
}

struct RepairedMovedWriter
{
    value:  s32
    cursor: *s32?
}

impl RepairedMovedWriter
{
    mtd opPostMove() { .cursor = &.value }
}

#test
{
    var source: RepairedMovedWriter
    source.cursor = &source.value
    var target = #move source
    target.cursor![] = 41
    Swag.assert(target.value == 41)
}

// An actual self-relocation, including one hidden behind pointers, keeps the value.
#[Swag.NoInline]
func relocatePossiblyAliased(target, source: *PackedMovedWriter) { target[] = #relocate source[] }

#test
{
    var source = PackedMovedWriter{value: 53}
    source.cursor = &source.value
    source        = #relocate source
    relocatePossiblyAliased(&source, &source)
    Swag.assert(source.value == 53 and source.cursor![] == 53)
}
