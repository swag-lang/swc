public const CTX_BASE_INIT_FLAG    = 0x0001'u64
public const CTX_BASE_PREMAIN_FLAG = 0x0002'u64
public const CTX_BASE_DROP_FLAG    = 0x0004'u64

#init
{
    @assert(@getcontext().allocator != null)
    @getcontext().user1 |= CTX_BASE_INIT_FLAG
    @getcontext().user3 += 1
}

#premain
{
    @assert((@getcontext().user1 & CTX_BASE_INIT_FLAG) != 0)
    @getcontext().user1 |= CTX_BASE_PREMAIN_FLAG
    @getcontext().user3 += 0x100
}

#drop
{
    @assert(@getcontext().user0 == 43)
    @getcontext().user1 |= CTX_BASE_DROP_FLAG
}

public func ctxBaseReadContext()->u64
{
    @assert(@getcontext().allocator != null)
    return @getcontext().user0
}

public func ctxBaseContextMarker()->u64
{
    @assert(@getcontext().allocator != null)
    return @getcontext().user2
}

public func ctxBaseInitCount()->u64
{
    @assert(@getcontext().allocator != null)
    return @getcontext().user3 & 0xFF
}

public func ctxBasePreMainCount()->u64
{
    @assert(@getcontext().allocator != null)
    return (@getcontext().user3 >> 8) & 0xFF
}
