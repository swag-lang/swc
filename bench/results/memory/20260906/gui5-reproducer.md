# Baseline GUI5 compiler reproducer

The full baseline and sanitizer candidate campaigns stop in the GUI5 release smoke with
`0xC0000005` at RVA `0x1BDC0`. The embedded symbols identify
`Gui5.onContrastPreviewEvent` (`main.swg:420`). The generated instruction dereferences a
selected packed color as an address. This standalone reduction needs no GUI module or window.

With the unchanged DevMode compiler from `89c7c0e7a`, save the following source to
`inline_selection.swg` and run:

```powershell
bin/swc.dm.exe test -f inline_selection.swg -bc release --artifact-kind executable --no-test-jit --num-cores 6
```

```swag
#global namespace InlineSelectionProbe

struct Packed
{
    bits: u32
}

impl Packed
{
    #[Swag.Inline, Swag.ConstExpr]
    func make(bits: u32)->Packed => {bits}
}

#[Swag.Inline]
func select(first: bool)->Packed => first ? Packed.make(0xFFFFFFFF) : Packed.make(0xFF000000)

#[Swag.NoInline]
func read(first: bool)->u32
{
    let value = select(first)
    return value.bits
}

#test
{
    Swag.assert(read(true) == 0xFFFFFFFF)
    Swag.assert(read(false) == 0xFF000000)
}
```

Observed: the generated test reads address `4294967295` in `InlineSelectionProbe.read` and
fails with hardware exception `3221225477`. The false branch is not reached after that failure.
The defect was subsequently fixed in `7f00d9f26`. Its
[native regression](../../../../bin/unittests/native/inline/return_conditional_small_struct.swg)
is preserved by the merge.
