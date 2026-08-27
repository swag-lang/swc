#global namespace InlineIndexedReceiverNarrowing

public struct Item
{
    public
    {
        storage: [1] u8
        buffer:  #null [*] u8
    }
}

impl Item
{
    #[Swag.Inline]
    mtd clearFirst()
    {
        if .buffer do
            .buffer[0] = 0
    }
}
