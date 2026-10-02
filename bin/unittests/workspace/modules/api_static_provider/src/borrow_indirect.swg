#global public

struct DepBorrowIndirectValue
{
    public item: *s32?
}

private var indirectGlobal = 37
private var indirectStored:  DepBorrowIndirectValue
private var indirectAddress: *DepBorrowIndirectValue?

#[Swag.NoInline]
func depBorrowIndirectGlobal()->*s32 => &indirectGlobal

#[Swag.NoInline]
func depBorrowIndirectCopyScalar(destination: *s32, source: *s32)
{
    destination[] = source[]
}

#[Swag.NoInline]
func depBorrowIndirectCopy(destination: *DepBorrowIndirectValue, source: *DepBorrowIndirectValue)
{
    destination[] = source[]
}

#[Swag.NoInline]
func depBorrowIndirectRead(source: *DepBorrowIndirectValue)->DepBorrowIndirectValue => source[]

#[Swag.NoInline]
func depBorrowIndirectStore(source: *DepBorrowIndirectValue)
{
    indirectStored = source[]
}

#[Swag.NoInline]
func depBorrowIndirectStoredValue()->s32 => indirectStored.item![]

#[Swag.NoInline]
func depBorrowIndirectKeepAddress(source: *DepBorrowIndirectValue)
{
    indirectAddress = source
}

// An older explicit direct mask remains conservative after indirect facts are added.
#[Swag.NoInline, Swag.BorrowSummary(0, into: 2)]
func depBorrowIndirectLegacyCopy(destination: *DepBorrowIndirectValue, source: *DepBorrowIndirectValue)
{
    destination[] = source[]
}
