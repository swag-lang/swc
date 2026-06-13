#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

struct PropHeadlessData
{
    count:      s32 = 42
    label:      string = "hello"
    enabled:    bool = true
}

// Properties.addStruct reflects a struct into one item per field (+ a section item).
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 320)

    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    // 1 implicit section item + 3 fields.
    @assert(prop.items.count == 4)
    @assert(prop.items[0].flags.has(.Section))

    host.shutdown()
}

// A named section becomes the first item and is registered.
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 320)

    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data, "Settings")

    @assert(prop.items.count == 4)
    @assert(prop.items[0].flags.has(.Section))
    @assert(prop.sections.count == 1)

    host.shutdown()
}
