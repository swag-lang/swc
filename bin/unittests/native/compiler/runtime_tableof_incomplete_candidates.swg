#global private
using Swag

interface ITableProbe
{
    mtd score()->s32
}

struct TableProbe
{
    value: s32
}

struct OtherProbe
{
    value: s32
}

impl ITableProbe for TableProbe
{
    mtd impl score()->s32 => .value
}

func runtimeTableOf(objectType, interfaceType: typeinfo)->const *void?
{
    return Swag.tableOf(objectType, interfaceType)
}

func canLookupImplementedTypeAtRuntime()
{
    discard runtimeTableOf(#typeof(TableProbe{}), #typeof(ITableProbe))
}

func materializeInterfaceTable()->bool
{
    var concrete         = TableProbe{value: 17}
    var itf: ITableProbe = concrete
    return itf.score() == 17
}

func hasNoRuntimeTableForUnimplementedType()->bool
{
    let table = runtimeTableOf(#typeof(OtherProbe{}), #typeof(ITableProbe))
    return table == null
}

#test
{
    Swag.assert(materializeInterfaceTable())
    canLookupImplementedTypeAtRuntime()
    Swag.assert(hasNoRuntimeTableForUnimplementedType())
    Swag.assert(runtimeTableOf(s32, ITableProbe) == null)
    Swag.assert(runtimeTableOf(TableProbe, s32) == null)
}
