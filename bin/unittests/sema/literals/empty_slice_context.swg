#global private

func emptySliceCount(values: const [..] string)->u64 => values.count
func emptySliceDefault(values: const [..] string = [])->u64 => values.count
func emptySliceReturn()->const [..] string => []

func emptySliceTypedUse()->u64
{
    let values: const [..] string = []
    return emptySliceCount(values) + emptySliceCount([]) + emptySliceDefault() + emptySliceReturn().count
}
