#global private

struct ConstCompareBox
{
    value: s32
}

impl ConstCompareBox
{
    #[Swag.ConstExpr]
    mtd const opCompare(other: ConstCompareBox)->s32
    {
        if .value < other.value do return -2147483648
        if .value > other.value do return 2147483647
        return 0
    }
}

const low  = ConstCompareBox{value: -3}
const high = ConstCompareBox{value: 9}

#assert(low < high)
#assert(low <= high)
#assert(not (low > high))
#assert(not (low >= high))
#assert(high > low)
#assert(high >= low)
#assert(not (high < low))
#assert(not (high <= low))
#assert(low <= low)
#assert(low >= low)
#assert(not (low < low))
#assert(not (low > low))
