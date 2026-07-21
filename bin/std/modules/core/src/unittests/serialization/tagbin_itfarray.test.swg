#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

// Round-trip of an array of BARE (non-null) interfaces: the decode path appends
// raw slots (no implicit default exists for a non-null interface) and fully
// initializes them from the stream.

interface ITagBinArrayThing
{
    mtd value()->s32;
}

struct TagBinArrayThing
{
    v: s32
}

impl ITagBinArrayThing for TagBinArrayThing
{
    mtd impl value()->s32 { return .v; }
}

struct TagBinArrayHolder
{
    things: Array'ITagBinArrayThing
}

func releaseTagBinArrayHolder(holder: *TagBinArrayHolder)
{
    for it in holder.things do
        Memory.delete(cast(*TagBinArrayThing) @dataof(it))
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
        holder.things.add(cast(ITagBinArrayThing) t)
    }
    defer releaseTagBinArrayHolder(&holder)

    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    var buffer:  ConcatBuffer
    catch encoder.writeAll(&buffer, holder)
    @assert(@err == null)

    buffer.makeLinear()
    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    var loaded  = catch decoder.readAll'TagBinArrayHolder(notnull buffer.toSlice())
    @assert(@err == null)
    defer releaseTagBinArrayHolder(notnull loaded)

    @assert(loaded.things.count == 3)
    for it, i in loaded.things do
        @assert(it.value() == cast(s32) (10 + i))
}
