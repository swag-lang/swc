#global public

// Interface call summaries for inline views must remain available to consumers.
interface DepBorrowWriter
{
    mtd print(text: string)
}

struct DepBorrowNonRetainingWriter
{
    public calls: u32
}

impl DepBorrowWriter for DepBorrowNonRetainingWriter
{
    mtd impl print(text: string)
    {
        discard text
        me.calls += 1
    }
}

var depBorrowStoredText: string?

struct DepBorrowRetainingWriter {}

impl DepBorrowRetainingWriter
{
    mtd store(text: string)
    {
        depBorrowStoredText = text
    }
}

impl DepBorrowWriter for DepBorrowRetainingWriter
{
    mtd impl print(text: string)
    {
        me.store(text)
    }
}
