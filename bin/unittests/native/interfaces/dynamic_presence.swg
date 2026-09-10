#global private

interface IMetadata
{
    mtd answer()->u32
}

struct Metadata {marker: u32}
struct Other {marker: u32}
struct Fallback {marker: u32}
#[Swag.Strict]
alias MetadataAlias = IMetadata

impl IMetadata for Metadata
{
    mtd impl answer()->u32 => 42
}

impl IMetadata for Fallback
{
    mtd impl answer()->u32 => 7
}

func metadata(type: const *Swag.TypeInfoStruct)->IMetadata?
{
    return Swag.makeInterface(null, type, IMetadata)
}

#test
{
    let value = metadata(#typeof(Metadata))
    let raw   = cast(const *Swag.Interface) &value
    Swag.assert(raw.obj == null)
    Swag.assert(raw.itable != null)
    let present = value!
    Swag.assert(present.answer() == 42)
}

#test
{
    let value = metadata(#typeof(Metadata))
    Swag.assert(cast(bool) value)
    Swag.assert(value != null)
    Swag.assert(not (value == null))
    Swag.assert(not (not value))
    Swag.assert(value and true)
    Swag.assert(false or value)
    Swag.assert((value ? 7 : 9) == 7)
    var seen = false
    if value do seen = true
    Swag.assert(seen)
    Swag.assert(value.answer() == 42)
    Swag.assert((value?.answer() orelse 0) == 42)
    let fallback = Swag.makeInterface(null, Fallback, IMetadata)
    let selected = value orelse fallback
    Swag.assert(selected.answer() == 42)
    Swag.assert(value != metadata(#typeof(Other)))
    Swag.assert(value != metadata(#typeof(Fallback)))
    Swag.assert(value == metadata(#typeof(Metadata)))
}

#test
{
    let value = metadata(#typeof(Other))
    Swag.assert(not cast(bool) value)
    Swag.assert(value == null)
    Swag.assert(not (value != null))
    Swag.assert(not value)
    Swag.assert(not (value and true))
    Swag.assert(not (false or value))
    Swag.assert((value ? 7 : 9) == 9)
    var seen = false
    if value do seen = true
    Swag.assert(not seen)
    Swag.assert((value?.answer() orelse 0) == 0)
    let fallback = Swag.makeInterface(null, Fallback, IMetadata)
    let selected = value orelse fallback
    Swag.assert(selected.answer() == 7)
}

#test
{
    const value = #run metadata(#typeof(Metadata))
    #assert(cast(bool) value)
    #assert(value != null)
    const missing = #run metadata(#typeof(Other))
    #assert(not cast(bool) missing)
    #assert(missing == null)
    const aliasMissing = cast(MetadataAlias?) missing
    #assert(aliasMissing == null)
    #assert(not cast(bool) aliasMissing)
    const fallback = #run metadata(#typeof(Fallback))
    const selected = missing orelse fallback
    #assert(cast(bool) selected)
    Swag.assert(selected!.answer() == 7)
}

#test
{
    var value = cast(MetadataAlias?) metadata(#typeof(Metadata))
    Swag.assert(cast(bool) value)
    Swag.assert(value != null)
    Swag.assert((value ? 1 : 2) == 1)
    let boxed     = Swag.makeAny(&value, #typeof(value))
    let extracted = cast(MetadataAlias) boxed
    Swag.assert((cast(IMetadata) extracted).answer() == 42)
    Swag.assert(metadata(#typeof(Metadata))!.answer() == 42)
    Swag.assert((metadata(#typeof(Metadata))?.answer() orelse 0) == 42)
}
