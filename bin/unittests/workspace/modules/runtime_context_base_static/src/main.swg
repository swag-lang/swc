public const CTX_BASE_INIT_FLAG    = 0x0001'u64
public const CTX_BASE_PREMAIN_FLAG = 0x0002'u64
public const CTX_BASE_DROP_FLAG    = 0x0004'u64

#init
{
    Swag.assert(Swag.getContext().allocator != null)
    Swag.getContext().user1 |= CTX_BASE_INIT_FLAG
    Swag.getContext().user3 += 1
}

#premain
{
    Swag.assert((Swag.getContext().user1 & CTX_BASE_INIT_FLAG) != 0)
    Swag.getContext().user1 |= CTX_BASE_PREMAIN_FLAG
    Swag.getContext().user3 += 0x100
}

#drop
{
    Swag.assert(Swag.getContext().user0 == 43)
    Swag.getContext().user1 |= CTX_BASE_DROP_FLAG
}

public func ctxBaseReadContext()->u64
{
    Swag.assert(Swag.getContext().allocator != null)
    return Swag.getContext().user0
}

public func ctxBaseContextMarker()->u64
{
    Swag.assert(Swag.getContext().allocator != null)
    return Swag.getContext().user2
}

public func ctxBaseInitCount()->u64
{
    Swag.assert(Swag.getContext().allocator != null)
    return Swag.getContext().user3 & 0xFF
}

public func ctxBasePreMainCount()->u64
{
    Swag.assert(Swag.getContext().allocator != null)
    return (Swag.getContext().user3 >> 8) & 0xFF
}
