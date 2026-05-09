#global fileprivate

struct(T) NativeGenericSizeEntry
{
    hash:   u32
    first:  T
    second: s32
}

struct(T) NativeGenericSizeBox
{
    entries: [*] NativeGenericSizeEntry
}

alias NativeGenericSizeEntryAlias = NativeGenericSizeEntry

impl NativeGenericSizeBox
{
    #[Swag.NoInline]
    mtd byteCount(count: u64)->u64
    {
        #assert(#sizeof(NativeGenericSizeEntry) == #sizeof(NativeGenericSizeEntry's32))
        #assert(#alignof(NativeGenericSizeEntry) == #alignof(NativeGenericSizeEntry's32))
        #assert(#sizeof(NativeGenericSizeEntryAlias) == #sizeof(NativeGenericSizeEntry's32))
        #assert(#alignof(NativeGenericSizeEntryAlias) == #alignof(NativeGenericSizeEntry's32))
        return count * #sizeof(NativeGenericSizeEntry) + #alignof(NativeGenericSizeEntry)
    }

    #[Swag.NoInline]
    mtd makeEntry(value: T)->NativeGenericSizeEntry
    {
        return {hash: 1, first: value, second: 2}
    }

    #[Swag.NoInline]
    mtd makeAliasedEntry(value: T)->NativeGenericSizeEntryAlias
    {
        return {hash: 3, first: value, second: 4}
    }
}

#test
{
    var box: NativeGenericSizeBox's32
    let entry = box.makeEntry(7)
    let aliasEntry = box.makeAliasedEntry(9)

    #assert(#typeof(entry) == NativeGenericSizeEntry's32)
    #assert(#typeof(aliasEntry) == NativeGenericSizeEntry's32)
    @assert(box.byteCount(4) == 52)
    @assert(entry.hash == 1)
    @assert(entry.first == 7)
    @assert(entry.second == 2)
    @assert(aliasEntry.hash == 3)
    @assert(aliasEntry.first == 9)
    @assert(aliasEntry.second == 4)
}
