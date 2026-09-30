#global private

var Drops: u32

struct Owner
{
    value:  u64
    pad:    [3] u64
    buffer: *u64?
}

impl Owner
{
    mtd opDrop()
    {
        Swag.assert(.value == 42 and .buffer == &.value)
        Drops += 1
    }

    mtd opPostCopy() { .buffer = &.value }
    mtd opPostMove() { .buffer = &.value }
}

struct Settings
{
    preset: u8
    level:  u8
    value:  Owner
}

struct Request
{
    source:   Owner
    stage:    Owner
    kind:     u32
    settings: Settings
}

func makeOwner()->Owner
{
    var result: retval
    result.value  = 42
    result.buffer = &result.value
    return result
}

func makeSettings()->Settings => {preset: 1, level: 2, value: makeOwner()}
func makeRequest()->Request => {source: makeOwner(), stage: makeOwner(), kind: 3, settings: makeSettings()}

// Inlined call results move into fields even when their storage has no pending drop.
// Copying a field out of the returned aggregate still leaves the aggregate to be dropped.
#test
{
    Drops = 0
    {
        let settings = makeRequest().settings
        Swag.assert(settings.value.value == 42 and settings.value.buffer == &settings.value.value)
        Swag.assert(settings.preset == 1 and settings.level == 2)
        Swag.assert(Drops == 3)
    }
    Swag.assert(Drops == 4)
}
