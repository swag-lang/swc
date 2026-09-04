#global private

struct(T) GenericSizeEntry
{
    hash:   u32
    first:  T
    second: s32
}

struct(T) GenericSizeBox
{
    entries: [*] GenericSizeEntry?
}

alias GenericSizeEntryAlias = GenericSizeEntry

impl GenericSizeBox
{
    #[Swag.NoInline]
    mtd byteCount(count: u64)->u64
    {
        #assert(#sizeof(GenericSizeEntry'(T)) == #sizeof(GenericSizeEntry's32))
        #assert(#alignof(GenericSizeEntry'(T)) == #alignof(GenericSizeEntry's32))
        #assert(#sizeof(GenericSizeEntryAlias'(T)) == #sizeof(GenericSizeEntry's32))
        #assert(#alignof(GenericSizeEntryAlias'(T)) == #alignof(GenericSizeEntry's32))
        return count * #sizeof(GenericSizeEntry'(T)) + #alignof(GenericSizeEntry'(T))
    }

    #[Swag.NoInline]
    mtd makeEntry(value: T)->GenericSizeEntry
    {
        return {hash: 1, first: value, second: 2}
    }

    #[Swag.NoInline]
    mtd makeAliasedEntry(value: T)->GenericSizeEntryAlias
    {
        return {hash: 3, first: value, second: 4}
    }
}

#test
{
    var box: GenericSizeBox's32
    let entry      = box.makeEntry(7)
    let aliasEntry = box.makeAliasedEntry(9)

    #assert(#offsetof(entry.hash) == 0)
    #assert(#offsetof(entry.first) == 4)
    #assert(#offsetof(entry.second) == 8)
    #assert(#offsetof(aliasEntry.hash) == 0)
    #assert(#offsetof(aliasEntry.first) == 4)
    #assert(#offsetof(aliasEntry.second) == 8)
    #assert(#typeof(entry) == GenericSizeEntry's32)
    #assert(#typeof(aliasEntry) == GenericSizeEntry's32)
    Swag.assert(box.byteCount(4) == 52)
    Swag.assert(entry.hash == 1)
    Swag.assert(entry.first == 7)
    Swag.assert(entry.second == 2)
    Swag.assert(aliasEntry.hash == 3)
    Swag.assert(aliasEntry.first == 9)
    Swag.assert(aliasEntry.second == 4)
}
