#global private

struct Owner { value: s32 }
impl Owner { mtd opDrop() {} }
struct Box { owner: Owner }

func borrowedMoveReference(source: #move Owner)
{
    let moved = Box{source}     // swc-expected-error {{sema_err_move_ref_type_context}}
}

#test
{
    var first, second: [1] Owner
    let selected = first[0].value == 0 ? first : #move second     // swc-expected-error {{sema_err_cannot_copy_owning}}
}

#test
{
    var first, second: Owner
    let selected = first.value == 0 ? first : #move second     // swc-expected-error {{sema_err_cannot_copy_owning}}
}

#test
{
    var first, second: Owner
    let selected = first.value == 0 ? #move first : second     // swc-expected-error {{sema_err_cannot_copy_owning}}
}

#test
{
    var source: Owner
    let copy = Box{source}     // swc-expected-error {{sema_err_cannot_copy_owning}}
}

#test
{
    let source = Owner{1}
    let moved  = Box{#move source}     // swc-expected-error {{sema_err_cannot_cast}}
}

struct RequiredOwner { value: *s32 }
impl RequiredOwner { mtd opDrop() {} }
struct RequiredBox { owner: RequiredOwner }

#test
{
    var value  = 1
    var source = RequiredOwner{&value}
    let moved  = RequiredBox{#move source}     // swc-expected-error {{sema_err_move_source_no_default}}
}

#test
{
    var value  = 1
    var source = RequiredOwner{&value}
    let moved  = value == 1 ? #move source : RequiredOwner{&value}     // swc-expected-error {{sema_err_move_source_no_default}}
}

#test
{
    var first, second: Owner
    let selected = first.value == 0 ? (second.value == 0 ? first : second) : #move first     // swc-expected-error {{sema_err_cannot_copy_owning}}
}
