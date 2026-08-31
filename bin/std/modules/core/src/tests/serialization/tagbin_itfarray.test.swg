#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// Round-trip of an array of BARE (non-null) interfaces: the decode path appends
// raw slots (no implicit default exists for a non-null interface) and fully
// initializes them from the stream.

interface ITagBinArrayThing
{
    mtd value()->s32
}

#[Serialization.TypeKey("core.test.tagbin-array-thing")]
struct TagBinArrayThing
{
    v: s32
}

impl ITagBinArrayThing for TagBinArrayThing
{
    mtd impl value()->s32
    {
        return .v
    }
}

#[Serialization.Schema("core.test.tagbin-array-holder")]
struct TagBinArrayHolder
{
    things: Array'ITagBinArrayThing
}

struct TagBinUnkeyedThing
{
    v: s32
}

impl ITagBinArrayThing for TagBinUnkeyedThing
{
    mtd impl value()->s32 => .v
}

#[Serialization.Schema("core.test.tagbin-unkeyed-holder")]
struct TagBinUnkeyedHolder
{
    thing: ITagBinArrayThing
}

#[Serialization.TypeKey("core.test.duplicate-thing")]
struct TagBinDuplicateThingA
{
    v: s32
}

impl ITagBinArrayThing for TagBinDuplicateThingA
{
    mtd impl value()->s32 => .v
}

#[Serialization.TypeKey("core.test.duplicate-thing")]
struct TagBinDuplicateThingB
{
    v: s32
}

impl ITagBinArrayThing for TagBinDuplicateThingB
{
    mtd impl value()->s32 => .v
}

#[Serialization.Schema("core.test.tagbin-duplicate-holder")]
struct TagBinDuplicateHolder
{
    thing: ITagBinArrayThing
}

func releaseTagBinArrayHolder(holder: *TagBinArrayHolder)
{
    for it in holder.things do
        Memory.delete(cast(*TagBinArrayThing) it.buffer)
    holder.things.clear()
}

#test
{
    Reflection.registerType(#typeof(TagBinArrayThing))

    var holder: TagBinArrayHolder
    for i in 3
    {
        let t = Memory.new'TagBinArrayThing()
        t.v = cast(s32) (10 + i)
        holder.things.add(t)
    }

    defer releaseTagBinArrayHolder(&holder)

    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    var buffer:  ConcatBuffer
    expect encoder.writeAll(&buffer, holder)
    buffer.makeLinear()
    Swag.assert(buffer.toString().contains("core.test.tagbin-array-thing"))
    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    let loaded = expect decoder.readAll'TagBinArrayHolder(buffer.toSlice()!)!
    defer releaseTagBinArrayHolder(loaded)

    Swag.assert(loaded.things.count == 3)
    for it, i in loaded.things do
        Swag.assert(it.value() == cast(s32) (10 + i))
}

// A dynamic object cannot fall back to its Swag type name.
#test
{
    let thing = Memory.new'TagBinUnkeyedThing()
    defer Memory.delete(thing)

    Reflection.registerType(#typeof(TagBinUnkeyedThing))
    var holder = TagBinUnkeyedHolder{thing: cast(ITagBinArrayThing) thing[]}

    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    var buffer:  ConcatBuffer
    catch encoder.writeAll(&buffer, holder) as err
    Swag.assert(err != null)
    Swag.assert(Utf8.contains(Errors.message(err), "Serialization.TypeKey"))
}

// A key shared by two concrete types is ambiguous and cannot reach the wire.
#test
{
    let thing = Memory.new'TagBinDuplicateThingA()
    defer Memory.delete(thing)

    Reflection.registerType(#typeof(TagBinDuplicateThingA))
    Reflection.registerType(#typeof(TagBinDuplicateThingB))
    var holder = TagBinDuplicateHolder{thing: cast(ITagBinArrayThing) thing[]}

    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    var buffer:  ConcatBuffer
    catch encoder.writeAll(&buffer, holder) as err
    Swag.assert(err != null)
    Swag.assert(Utf8.contains(Errors.message(err), "does not resolve to one registered type"))
}
