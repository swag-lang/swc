#global public

private struct OpaqueUnionSparsePayload
{
    zeros:  [128] u8
    marker: u64 = 0x0102030405060708
}

#[Swag.Opaque]
union OpaqueSparseUnion
{
    private
    {
        ignored: u64
        value:   OpaqueUnionSparsePayload
    }
}

impl OpaqueSparseUnion
{
    #[Swag.NoInline]
    mtd const isDefault()->bool
    {
        for byte in .value.zeros where byte != 0 do
            return false
        return .value.marker == 0x0102030405060708
    }

    #[Swag.NoInline]
    mtd change() { .value.zeros[0] = 7; .value.marker = 0 }
}

private struct OpaqueUnionTextPayload
{
    zeros:  [128] u8
    marker: u64    = 37
    text:   string = "union-text"
}

#[Swag.Opaque]
union OpaqueTextUnion
{
    private
    {
        ignored: u64
        value:   OpaqueUnionTextPayload
    }
}

impl OpaqueTextUnion
{
    #[Swag.NoInline]
    mtd const isDefault()->bool => .value.zeros[0] == 0 and .value.marker == 37 and .value.text == "union-text"

    #[Swag.NoInline]
    mtd change() { .value.zeros[0] = 7; .value.marker = 0; .value.text = "changed" }
}

private const OPAQUE_UNION_PROVIDER_TEXT = "union-provider-identity"

#[Swag.Opaque]
union OpaquePointerUnion
{
    private
    {
        ignored: u64
        address: const [*] u8 = OPAQUE_UNION_PROVIDER_TEXT.buffer
    }
}

impl OpaquePointerUnion
{
    #[Swag.NoInline]
    mtd const isDefault()->bool => .address == OPAQUE_UNION_PROVIDER_TEXT.buffer

    #[Swag.NoInline]
    mtd change() { .address = "changed".buffer }
}

#[Swag.NoInline]
func opaqueUnionSourceControl()->bool
{
    var sparse:  OpaqueSparseUnion
    var text:    OpaqueTextUnion
    var pointer: OpaquePointerUnion
    return #sizeof(OpaqueSparseUnion) == 136 and #sizeof(OpaqueTextUnion) == 152 and
           #sizeof(OpaquePointerUnion) == 8 and sparse.isDefault() and text.isDefault() and pointer.isDefault()
}
