#global fileprivate // swc-option sema-only
#global skip
#test
{
    let contentHeight = 40
    let hasHeader     = true
    let rowHeight     = contentHeight + (hasHeader ? 50 : 20)
    @assert(rowHeight == 90)
}
