#global if #command == Swag.CompilerCommand.Test
#global private

using Core
using StaticApi

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let item = cast(*s32, Memory.alloc(#sizeof(s32)))
    item[] = 7
    var box: *s32? = item
    depReleaseBox(&box)          // swc-expected-note {{sanity_note_pointer_released_here}}
    Swag.assert(item[] == 7)     // swc-expected-error {{sanity_err_use_after_free}}
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let item = cast(*s32, Memory.alloc(#sizeof(s32)))
    item[] = 8
    var box: *s32? = item
    depReleaseBoxOuter(&box)     // swc-expected-note {{sanity_note_pointer_released_here}}
    Swag.assert(item[] == 8)     // swc-expected-error {{sanity_err_use_after_free}}
}

// An importer can forward the summary again without seeing the provider's body.
#[Swag.NoInline]
func importedReleaseBox(box: *(*s32?)) => depReleaseBoxOuter(box)

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let item = cast(*s32, Memory.alloc(#sizeof(s32)))
    item[] = 9
    var box: *s32? = item
    importedReleaseBox(&box)     // swc-expected-note {{sanity_note_pointer_released_here}}
    Swag.assert(item[] == 9)     // swc-expected-error {{sanity_err_use_after_free}}
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let item = cast(*s32, Memory.alloc(#sizeof(s32)))
    item[] = 12
    var other: *s32?
    var box:   *s32? = item
    depReleaseSecondBox(&other, &box)     // swc-expected-note {{sanity_note_pointer_released_here}}
    Swag.assert(item[] == 12)             // swc-expected-error {{sanity_err_use_after_free}}
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    var box: *s32? = cast(*s32, Memory.alloc(#sizeof(s32)))
    depReleaseBoxOuter(&box)
    Swag.assert(box == null)
    box   = cast(*s32, Memory.alloc(#sizeof(s32)))
    box[] = 10
    Swag.assert(box[] == 10)
    importedReleaseBox(&box)
    Swag.assert(box == null)

    // A different box argument must retain its independently allocated contents.
    var other: *s32? = cast(*s32, Memory.alloc(#sizeof(s32)))
    other![] = 14
    box      = cast(*s32, Memory.alloc(#sizeof(s32)))
    depReleaseSecondBox(&other, &box)
    Swag.assert(other![] == 14 and box == null)
    importedReleaseBox(&other)
}
