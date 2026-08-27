#global private

struct NullNarrowInlineIndexItem
{
    buffer: #null [*] u8
}

struct NullNarrowInlineIndexHolder
{
    item: NullNarrowInlineIndexItem
}

impl NullNarrowInlineIndexItem
{
    #[Swag.Inline]
    mtd clearFirst()
    {
        if .buffer do
            .buffer[0] = 0
    }
}

func nullNarrowInlineIndexedReceiver(items: [..] NullNarrowInlineIndexItem)
{
    items[0].clearFirst()
}

func nullNarrowInlineLocalReceiver()
{
    var item: NullNarrowInlineIndexItem
    item.clearFirst()
}

func nullNarrowInlineFieldReceiver(holder: *NullNarrowInlineIndexHolder)
{
    holder.item.clearFirst()
}
