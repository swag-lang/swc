#global private

// Each detached with subject re-expands an inline index operator in its own context.

struct(T) Items { buffer: [*] T }
impl Items
{
    #[Swag.Inline]
    mtd opIndexPtr(index: u64)->*T => .buffer + index
}
struct Child { value: u64 }
struct Cell { value: u64; child: Child; hook: (func||()->u64)? }
struct Owner { cells: Items'(*Cell); value: u64 = 42 }
func setup(owner: *Owner)
{
    for slot in 3
    {
        with owner.cells[slot]
        {
            .value = slot
            .hook  = func|owner|()->u64 { return owner.value }
        }

        with owner.cells[slot].child
        {
            .value = slot + 5
        }
    }
}
#test
{
    var cells: [3] Cell
    var pointers = [&cells[0], &cells[1], &cells[2]]
    var owner    = Owner{cells: {buffer: pointers.buffer}}
    setup(&owner)
    for slot in 3 do
        Swag.assert(cells[slot].value == slot and
                    cells[slot].child.value == slot + 5 and
                    cells[slot].hook!() == 42)
}
