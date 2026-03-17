#global fileprivate // swc-option sema-only
#global skip
#test
{
    @assert(@getcontext().flags & Swag.ContextFlags.Test ? true : false)
}
