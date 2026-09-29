#global private
using Swag

var limit: u64

// The body changes the global bound, so the next header must reload it.
#[Swag.Optimize(true), Swag.NoInline]
func visitTreeIndices()->u64
{
    var index = 0'u64
    var total = 0'u64
    while true
    {
        let next = 2 * index + 1
        if next >= limit do break
        limit += 1
        total += next
        index = next
    }
    return total
}

func checkRotatedHeader()->bool
{
    limit = 8
    if visitTreeIndices() != 11 or limit != 11 do return false
    limit = 40
    return visitTreeIndices() == 57 and limit == 45
}

#assert(#run checkRotatedHeader())

#test
{
    Swag.assert(checkRotatedHeader())
}
