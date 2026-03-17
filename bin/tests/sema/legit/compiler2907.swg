#global fileprivate // swc-option sema-only
#global skip
const BUF = "toto\tla\tfripouille是"
#test
{
    @assert(@countof(BUF) == 21)
}
