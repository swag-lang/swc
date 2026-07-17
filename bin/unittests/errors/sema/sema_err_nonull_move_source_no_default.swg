#global private

struct NonNullMoveSourceItem
{
    value: s32
}

struct NonNullMoveSourceOwner
{
    required: #nonull *NonNullMoveSourceItem
}

impl NonNullMoveSourceOwner
{
    mtd opDrop()
    {
    }
}

func consumeNonNullMoveSource(value: NonNullMoveSourceOwner)
{
}

func forwardNonNullMoveSource(value: #fwd NonNullMoveSourceOwner)
{
    var target = NonNullMoveSourceOwner{required: value.required}
    target = #fwd value // swc-expected-error {{sema_err_move_source_no_default}}
}

#test
{
    var item = NonNullMoveSourceItem{value: 1}
    var source = NonNullMoveSourceOwner{required: &item}
    var target = NonNullMoveSourceOwner{required: &item}
    target = #move source // swc-expected-error {{sema_err_move_source_no_default}}
}

#test
{
    var item = NonNullMoveSourceItem{value: 1}
    var source = NonNullMoveSourceOwner{required: &item}
    var target = #move source // swc-expected-error {{sema_err_move_source_no_default}}
}

#test
{
    var item = NonNullMoveSourceItem{value: 1}
    var source = NonNullMoveSourceOwner{required: &item}
    consumeNonNullMoveSource(#move source) // swc-expected-error {{sema_err_move_source_no_default}}
}
