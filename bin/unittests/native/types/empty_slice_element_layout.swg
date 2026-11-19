#global private

struct SliceHolder
{
    items: const [..] Element = []
}

struct Element
{
    // Instantiating the empty slice cannot depend on the element's layout.
    bytes: [#sizeof(DefaultHolder)] u8
}

const DefaultHolder = SliceHolder{}
#assert(DefaultHolder.items.count == 0 and DefaultHolder.items.buffer != null)

#test
{
    var holder: SliceHolder
    Swag.require(holder.items.count == 0 and holder.items.buffer != null)
}
