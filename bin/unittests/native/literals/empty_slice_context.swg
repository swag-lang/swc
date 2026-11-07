#global private

alias EmptySliceAlias = const [..] string

func emptySliceCount(values: const [..] string)->u64 => values.count
func emptySliceDefault(values: const [..] string = [])->u64 => values.count
func emptySliceReturn()->const [..] string => []

#test
{
    let values: const [..] string = []
    Swag.require(values.count == 0)
    Swag.require(values != null)
    Swag.require(emptySliceCount([]) == 0)
    Swag.require(emptySliceDefault() == 0)
    Swag.require(emptySliceReturn().count == 0)

    let mutableValues: [..] u32 = []
    Swag.require(mutableValues.count == 0)
    Swag.require(mutableValues != null)

    let aliased: EmptySliceAlias = []
    Swag.require(aliased.count == 0)
}
