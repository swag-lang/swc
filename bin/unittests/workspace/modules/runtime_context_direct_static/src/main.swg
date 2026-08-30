public const CTX_DIRECT_INIT_FLAG    = 0x0040'u64
public const CTX_DIRECT_PREMAIN_FLAG = 0x0080'u64
public const CTX_DIRECT_DROP_FLAG    = 0x0100'u64

#init
{
    Swag.assert(Swag.getContext().allocator != null)
    Swag.getContext().user1 |= CTX_DIRECT_INIT_FLAG
}

#premain
{
    Swag.assert((Swag.getContext().user1 & CTX_DIRECT_INIT_FLAG) != 0)
    Swag.getContext().user1 |= CTX_DIRECT_PREMAIN_FLAG
}

#drop
{
    Swag.assert(Swag.getContext().user0 == 43)
    Swag.getContext().user1 |= CTX_DIRECT_DROP_FLAG
}

public func ctxDirectReadContext()->u64
{
    Swag.assert(Swag.getContext().allocator != null)
    return Swag.getContext().user0
}

public func ctxDirectContextMarker()->u64
{
    Swag.assert(Swag.getContext().allocator != null)
    return Swag.getContext().user2
}
