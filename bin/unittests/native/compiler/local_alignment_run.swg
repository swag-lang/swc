#global private

#[Swag.Align(64)]
struct CompilerAlignedLocal
{
    values: [8]u64
}

#run
{
    var values: [2]CompilerAlignedLocal
    Swag.assert(cast(u64, &values) % 64 == 0)
    Swag.assert(cast(u64, &values[1]) % 64 == 0)
}

#test
{
    var value: CompilerAlignedLocal
    Swag.assert(cast(u64, &value) % 64 == 0)
}

const PersistentAlignedWords: const [..]u64 = #run
{
    var value: CompilerAlignedLocal
    Swag.assert(cast(u64, &value) % 64 == 0)
    for &entry, index in value.values do
        entry[] = 31 + index
    return cast(const [..]u64, value.values)
}

#test
{
    Swag.assert(PersistentAlignedWords.count == 8)
    for entry, index in PersistentAlignedWords do
        Swag.assert(entry == 31 + index)
}
