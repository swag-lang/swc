#global private

struct Bits { words: [4] u64 }

impl Bits
{
    #[Swag.NoInline]
    mtd set(index: u32) { .words[index >> 6] |= 1'u64 << (index & 63) }
}

var observations: u64

#[Swag.NoInline]
func readBesideExternalWrite(value: Bits)->u64
{
    observations += 1
    return value.words[0]
}

func localMethodKeepsStoragePrivate()->bool
{
    var value: Bits
    value.set(3)
    return readBesideExternalWrite(value) == 8
}

const LOCAL_METHOD_KEEPS_STORAGE_PRIVATE = #run localMethodKeepsStoragePrivate()

#test
{
    Swag.assert(LOCAL_METHOD_KEEPS_STORAGE_PRIVATE)
    Swag.assert(localMethodKeepsStoragePrivate())
}
