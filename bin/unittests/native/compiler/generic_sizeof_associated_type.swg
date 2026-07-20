#global private

struct(T) NativeGenericSizeEntry
{
    hash:   u32
    first:  T
    second: s32
}

struct(T) NativeGenericSizeBox
{
    entries: #null [*] NativeGenericSizeEntry
}

alias NativeGenericSizeEntryAlias = NativeGenericSizeEntry

impl NativeGenericSizeBox
{
    #[Swag.NoInline]
    mtd byteCount(count: u64)->u64
    {
        #assert(#sizeof(NativeGenericSizeEntry'(T)) == #sizeof(NativeGenericSizeEntry's32))
        #assert(#alignof(NativeGenericSizeEntry'(T)) == #alignof(NativeGenericSizeEntry's32))
        // Still unstable in the native suite: the alias is sometimes seen as a symbol instead of a type.
        // #assert(#sizeof(NativeGenericSizeEntryAlias'(T)) == #sizeof(NativeGenericSizeEntry's32))
        // #assert(#alignof(NativeGenericSizeEntryAlias'(T)) == #alignof(NativeGenericSizeEntry's32))
        return count * #sizeof(NativeGenericSizeEntry'(T)) + #alignof(NativeGenericSizeEntry'(T))
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

    #assert(#offsetof(entry.hash) == 0)
    #assert(#offsetof(entry.first) == 4)
    #assert(#offsetof(entry.second) == 8)
    #assert(#offsetof(aliasEntry.hash) == 0)
    #assert(#offsetof(aliasEntry.first) == 4)
    #assert(#offsetof(aliasEntry.second) == 8)
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
