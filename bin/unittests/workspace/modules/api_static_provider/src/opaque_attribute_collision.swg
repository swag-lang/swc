#global public

namespace OpaqueAttributeCollision
{
    attr Opaque()

    private const DEFAULT_TEXT = "opaque-attribute-collision"
    private var dropCount = 0

    private struct Payload
    {
        armed: bool
    }

    impl Payload
    {
        private mtd opDrop()
        {
            if .armed do
                dropCount += 1
        }
    }

    // The private address needs the provider's initializer, and the field owns cleanup.
    #[Swag.Opaque]
    struct Value
    {
        private
        {
            address: const [*] u8 = DEFAULT_TEXT.buffer
            payload: Payload
        }
    }

    impl Value
    {
        #[Swag.NoInline]
        mtd const isDefault()->bool => .address == DEFAULT_TEXT.buffer and not .payload.armed

        #[Swag.NoInline]
        mtd arm() { .payload.armed = true }
    }

    #[Swag.Opaque]
    struct Scalar
    {
        private value = 43
    }

    impl Scalar
    {
        #[Swag.NoInline]
        mtd const isDefault()->bool => .value == 43
    }

    #[Swag.Opaque]
    struct Required
    {
        private text: string
    }

    impl Required
    {
        #[Swag.NoInline]
        mtd opSet(value: string) { .text = value }

        #[Swag.NoInline]
        mtd const isReady()->bool => .text == "ready"
    }

    // The user's attribute remains usable in the same namespace.
    #[Opaque]
    struct Tagged
    {
        public value: s32
    }

    #[Swag.NoInline]
    func resetDrops() { dropCount = 0 }

    #[Swag.NoInline]
    func drops()->s32 => dropCount
}
