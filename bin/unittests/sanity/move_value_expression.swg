#global private
#global #[Swag.Sanity(.Lifecycle, true)]

struct Item { x, y: u32 }
struct Box { item: Item }

#test
{
    var source = Item{1, 2}
    let box    = Box{#move source}     // swc-expected-note {{sanity_note_move_origin}}
    Swag.assert(source.x == 1)         // swc-expected-error {{sanity_err_use_after_move}}
}

#test
{
    var source = Item{1, 2}
    let items  = [#move source]     // swc-expected-note {{sanity_note_move_origin}}
    Swag.assert(source.y == 2)      // swc-expected-error {{sanity_err_use_after_move}}
}
