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
    let raw   = cast(const *Swag.Interface, &value)
    Swag.require(raw.obj == null)
    Swag.require(raw.itable != null)
    let present = unwrap value
    Swag.require(present.answer() == 42)
}

#test
{
    let value = metadata(#typeof(Metadata))
    Swag.require(cast(bool, value))
    Swag.require(value != null)
    Swag.require(not (value == null))
    Swag.require(not (not value))
    Swag.require(value and true)
    Swag.require(false or value)
    Swag.require((value ? 7 : 9) == 7)
    var seen = false
    if value do seen = true
    Swag.require(seen)
    Swag.require(value.answer() == 42)
    Swag.require((value?.answer() orelse 0) == 42)
    let fallback = Swag.makeInterface(null, Fallback, IMetadata)
    let selected = value orelse fallback
    Swag.require(selected.answer() == 42)
    Swag.require(value != metadata(#typeof(Other)))
    Swag.require(value != metadata(#typeof(Fallback)))
    Swag.require(value == metadata(#typeof(Metadata)))
}

#test
{
    let value = metadata(#typeof(Other))
    Swag.require(not cast(bool, value))
    Swag.require(value == null)
    Swag.require(not (value != null))
    Swag.require(not value)
    Swag.require(not (value and true))
    Swag.require(not (false or value))
    Swag.require((value ? 7 : 9) == 9)
    var seen = false
    if value do seen = true
    Swag.require(not seen)
    Swag.require((value?.answer() orelse 0) == 0)
    let fallback = Swag.makeInterface(null, Fallback, IMetadata)
    let selected = value orelse fallback
    Swag.require(selected.answer() == 7)
}

#test
{
    const value = #run metadata(#typeof(Metadata))
    #assert(cast(bool, value))
    #assert(value != null)
    const missing = #run metadata(#typeof(Other))
    #assert(not cast(bool, missing))
    #assert(missing == null)
    const aliasMissing = cast(MetadataAlias?, missing)
    #assert(aliasMissing == null)
    #assert(not cast(bool, aliasMissing))
    const fallback = #run metadata(#typeof(Fallback))
    const selected = missing orelse fallback
    #assert(cast(bool, selected))
    Swag.require(selected!.answer() == 7)
}

#test
{
    var value = cast(MetadataAlias?, metadata(#typeof(Metadata)))
    Swag.require(cast(bool, value))
    Swag.require(value != null)
    Swag.require((value ? 1 : 2) == 1)
    let boxed     = Swag.makeAny(&value, #typeof(value))
    let extracted = assume cast (MetadataAlias, boxed)
    Swag.require(cast(IMetadata, extracted).answer() == 42)
    Swag.require(metadata(#typeof(Metadata))!.answer() == 42)
    Swag.require((metadata(#typeof(Metadata))?.answer() orelse 0) == 42)
}
