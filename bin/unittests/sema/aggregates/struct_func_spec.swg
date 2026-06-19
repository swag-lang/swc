#global fileprivate

struct SpecA
{
    value: s32
}

struct SpecB
{
    value: s32
}

interface I {}

struct SpecSlice
{
    values: [2] s32
}

impl SpecSlice
{
    mtd opCount() -> u64 { return 2; }
    mtd opSlice(low: u64, up: u64) -> [..] s32 { return @mkslice(&.values[low], (up + 1) - low); }
}
