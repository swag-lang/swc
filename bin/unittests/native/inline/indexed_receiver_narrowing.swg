#global private

#test
{
    var items: [2] InlineIndexedReceiverNarrowing.Item
    items[0].storage[0] = 11
    items[1].storage[0] = 22
    items[0].buffer     = cast([*] u8) &items[0].storage[0]
    items[1].buffer     = cast([*] u8) &items[1].storage[0]

    items[1].clearFirst()

    @assert(items[0].storage[0] == 11)
    @assert(items[1].storage[0] == 0)
}
