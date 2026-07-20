#global private

struct(T) SemaGenericSizeEntry
{
    hash:   u32
    first:  T
    second: s32
}

struct(T) SemaGenericSizeBox
{
    entries: #null [*] SemaGenericSizeEntry
}

alias SemaGenericSizeEntryAlias = SemaGenericSizeEntry

impl SemaGenericSizeBox
{
    func byteCount(count: u64)->u64
    {
        #assert(#sizeof(SemaGenericSizeEntry'(T)) == #sizeof(SemaGenericSizeEntry's32))
        #assert(#alignof(SemaGenericSizeEntry'(T)) == #alignof(SemaGenericSizeEntry's32))
        #assert(#sizeof(SemaGenericSizeEntryAlias'(T)) == #sizeof(SemaGenericSizeEntry's32))
        #assert(#alignof(SemaGenericSizeEntryAlias'(T)) == #alignof(SemaGenericSizeEntry's32))
        return count * #sizeof(SemaGenericSizeEntry'(T)) + #alignof(SemaGenericSizeEntry'(T))
    }

    func makeEntry(value: T)->SemaGenericSizeEntry
    {
        return {hash: 1, first: value, second: 2}
    }

    func makeAliasedEntry(value: T)->SemaGenericSizeEntryAlias
    {
        return {hash: 3, first: value, second: 4}
    }
}

func semaTest001()
{
    var box: SemaGenericSizeBox's32
    let stride = box.byteCount(4)
    let entry = box.makeEntry(7)
    let aliasEntry = box.makeAliasedEntry(9)

    #assert(#offsetof(entry.hash) == 0)
    #assert(#offsetof(entry.first) == 4)
    #assert(#offsetof(entry.second) == 8)
    #assert(#offsetof(aliasEntry.hash) == 0)
    #assert(#offsetof(aliasEntry.first) == 4)
    #assert(#offsetof(aliasEntry.second) == 8)
    #assert(#typeof(stride) == u64)
    #assert(#typeof(entry) == SemaGenericSizeEntry's32)
    #assert(#typeof(aliasEntry) == SemaGenericSizeEntry's32)
    #assert(#typeof(entry.first) == s32)
    #assert(#typeof(aliasEntry.first) == s32)
    #assert(#sizeof(SemaGenericSizeEntry's32) == 12)
    #assert(#alignof(SemaGenericSizeEntry's32) == 4)
}
