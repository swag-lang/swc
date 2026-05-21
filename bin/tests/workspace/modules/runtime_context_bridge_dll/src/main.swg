using RuntimeCtxBase

public const CTX_SHARED_INIT_FLAG    = 0x0008'u64
public const CTX_SHARED_PREMAIN_FLAG = 0x0010'u64
public const CTX_SHARED_DROP_FLAG    = 0x0020'u64

#init
{
    @assert((@getcontext().user1 & CTX_BASE_INIT_FLAG) != 0)
    @assert(@getcontext().allocator != null)
    @getcontext().user1 |= CTX_SHARED_INIT_FLAG
}

#premain
{
    @assert((@getcontext().user1 & CTX_BASE_PREMAIN_FLAG) != 0)
    @getcontext().user1 |= CTX_SHARED_PREMAIN_FLAG
}

#drop
{
    @assert(@getcontext().user0 == 43)
    @getcontext().user1 |= CTX_SHARED_DROP_FLAG
}

public func ctxSharedReadContext()->u64
{
    return ctxBaseReadContext()
}

public func ctxSharedContextMarker()->u64
{
    return ctxBaseContextMarker()
}
