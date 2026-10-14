#global private

var LastDropAddress: u64
var DropCount:       u32

struct SelfValue
{
    value, padding: u64
    target:         *u64?
}

impl SelfValue
{
    #[Implicit]
    mtd opSet(value: u64)
    {
        .value  = value
        .target = &.value
    }

    mtd opPostCopy() { .target = &.value }

    mtd opDrop()
    {
        LastDropAddress = cast(u64, me)
        DropCount       += 1
    }
}

struct Entry { value: SelfValue }

impl Entry
{
    #[Swag.NoInline]
    mtd replace(value: SelfValue) { .value = #nodrop value }
}

struct Owner
{
    direct:  Entry
    indexed: [2] Entry
}

impl Owner
{
    #[Swag.NoInline]
    mtd replaceDirect(value: SelfValue) { .direct.replace(value) }

    #[Swag.NoInline]
    mtd replaceIndexed(index: u64, value: SelfValue) { .indexed[index].replace(value) }
}

#test
{
    DropCount = 0
    var owner: Owner
    owner.replaceDirect(181)
    Swag.assert(owner.direct.value.value == 181)
    Swag.assert(owner.direct.value.target![] == 181)
    Swag.assert(DropCount == 1 and LastDropAddress != 0)
    owner.replaceIndexed(1, 191)
    Swag.assert(owner.indexed[1].value.value == 191)
    Swag.assert(owner.indexed[1].value.target![] == 191)
    Swag.assert(DropCount == 2)
}
