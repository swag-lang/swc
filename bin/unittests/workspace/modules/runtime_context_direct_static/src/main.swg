public const CTX_DIRECT_INIT_FLAG    = 0x0040'u64
public const CTX_DIRECT_PREMAIN_FLAG = 0x0080'u64
public const CTX_DIRECT_DROP_FLAG    = 0x0100'u64

#init
{
    @assert(@getcontext().allocator != null)
    @getcontext().user1 |= CTX_DIRECT_INIT_FLAG
}

#premain
{
    @assert((@getcontext().user1 & CTX_DIRECT_INIT_FLAG) != 0)
    @getcontext().user1 |= CTX_DIRECT_PREMAIN_FLAG
}

#drop
{
    @assert(@getcontext().user0 == 43)
    @getcontext().user1 |= CTX_DIRECT_DROP_FLAG
}

public func ctxDirectReadContext()->u64
{
    @assert(@getcontext().allocator != null)
    return @getcontext().user0
}

public func ctxDirectContextMarker()->u64
{
    @assert(@getcontext().allocator != null)
    return @getcontext().user2
}
