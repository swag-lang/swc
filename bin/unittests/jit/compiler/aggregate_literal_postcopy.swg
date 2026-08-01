#global private

var AggregateLiteralPostCopyCount: u32
var AggregateLiteralDropCount:     u32

struct AggregateLiteralTracked
{
    value: s32
}

impl AggregateLiteralTracked
{
    mtd opPostCopy()
    {
        AggregateLiteralPostCopyCount += 1
        .value                        += 100
    }

    mtd opDrop()
    {
        AggregateLiteralDropCount += 1
    }
}

#test
{
    AggregateLiteralPostCopyCount = 0
    AggregateLiteralDropCount     = 0

    {
        var source                              = AggregateLiteralTracked{7}
        var values: [1] AggregateLiteralTracked = [source]

        @assert(AggregateLiteralPostCopyCount == 1)
        @assert(source.value == 7)
        @assert(values[0].value == 107)
    }

    @assert(AggregateLiteralDropCount == 2)
}
