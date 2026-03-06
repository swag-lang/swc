#global fileprivate
#global skip
const BUF = "toto\tla\tfripouille是"
#test
{
    @assert(@countof(BUF) == 21)
}
