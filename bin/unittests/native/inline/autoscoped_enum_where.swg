#global private

enum InlineBug9Content: u8
{
    White
    Black
    Empty
    Invalid
}

struct InlineBug9Cell
{
    content: InlineBug9Content
}

#[Swag.Inline]
func inlineBug9Find(cells: [*] InlineBug9Cell, color: InlineBug9Content)->s8
{
    for i in 4's8 where cells[i].content == color do
        return i
    return -1
}

func inlineBug9Check(cells: [*] InlineBug9Cell, white: bool)->s8
{
    return inlineBug9Find(cells, white ? .White : .Black)
}

#test
{
    var cells: [4] InlineBug9Cell
    cells[0].content = .Empty
    cells[1].content = .White
    cells[2].content = .Black
    cells[3].content = .Invalid

    @assert(inlineBug9Check(&cells[0], true) == 1)
    @assert(inlineBug9Check(&cells[0], false) == 2)
}
