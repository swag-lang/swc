#global public

#[Swag.Opaque]
struct OpaqueDefaultScalar
{
    private
    {
        succeeded  = true
        count: s32 = 37
    }
}

impl OpaqueDefaultScalar
{
    #[Swag.NoInline]
    mtd const isDefault()->bool => .succeeded and .count == 37
    #[Swag.NoInline]
    mtd change() { .succeeded = false; .count = -1 }
}

#[Swag.Opaque]
struct OpaqueDefaultText
{
    private
    {
        prefix:      u8         = 3
        text:        string     = "ready\n\"quoted\"\\path\0end"
        names:       [2] string = ["first", "second"]
        unicodeText: string     = "\x80\xFF\u00E9\U0001F642"
        optional:    string?
        suffix:      u16        = 513
    }
}

impl OpaqueDefaultText
{
    #[Swag.NoInline]
    mtd const isDefault()->bool
    {
        return .prefix == 3 and .text == "ready\n\"quoted\"\\path\0end" and
               .names[0] == "first" and .names[1] == "second" and
               .unicodeText == "\x80\xFF\u00E9\U0001F642" and
               .optional == null and .suffix == 513
    }

    #[Swag.NoInline]
    mtd change() { .text = "changed"; .suffix = 0 }
}

#[Swag.Opaque]
struct OpaqueDefaultNested
{
    private
    {
        scalar: OpaqueDefaultScalar
        texts:  [2] OpaqueDefaultText
        tail:   u64 = 0x12345678
    }
}

impl OpaqueDefaultNested
{
    #[Swag.NoInline]
    mtd const isDefault()->bool => .scalar.isDefault() and .texts[0].isDefault() and .texts[1].isDefault() and .tail == 0x12345678
    #[Swag.NoInline]
    mtd change() { .scalar.change(); .texts[1].change(); .tail = 0 }
}

// This address must keep its identity in the provider, rather than point at a copied literal.
private const OPAQUE_DEFAULT_POINTER_TEXT = "provider-owned-default"

#[Swag.Opaque]
struct OpaqueDefaultPointer
{
    private address: const [*] u8 = OPAQUE_DEFAULT_POINTER_TEXT.buffer
}

impl OpaqueDefaultPointer
{
    #[Swag.NoInline]
    mtd const isDefault()->bool => .address == OPAQUE_DEFAULT_POINTER_TEXT.buffer
    #[Swag.NoInline]
    mtd change() { .address = "changed".buffer }
}

#[Swag.Opaque]
struct OpaqueDefaultPointerNested
{
    private values: [2] OpaqueDefaultPointer
}

impl OpaqueDefaultPointerNested
{
    #[Swag.NoInline]
    mtd const isDefault()->bool => .values[0].isDefault() and .values[1].isDefault()
    #[Swag.NoInline]
    mtd change() { .values[0].change(); .values[1].change() }
}

#[Swag.Opaque]
struct OpaqueRequiredDefault
{
    private text: string
}

impl OpaqueRequiredDefault
{
    #[Swag.NoInline]
    mtd opSet(value: string) { .text = value }
    #[Swag.NoInline]
    mtd const isReady()->bool => .text == "ready"
}
