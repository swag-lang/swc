#global fileprivate

interface IQualifiedUsing
{
    mtd value() -> s32;
}

struct QualifiedUsingBase
{
}

impl IQualifiedUsing for QualifiedUsingBase
{
    mtd impl value() -> s32
    {
        return 42;
    }
}

struct QualifiedUsingDerived
{
    using base: QualifiedUsingBase
}

impl IQualifiedUsing for QualifiedUsingDerived
{
}

#test
{
    var derived: QualifiedUsingDerived
    @assert(derived.IQualifiedUsing.value() == 42)
}
