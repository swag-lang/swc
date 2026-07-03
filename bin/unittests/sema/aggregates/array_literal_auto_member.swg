#global private

enum PieceKind: u8 { Rook, Knight, Bishop, Queen, King, Pawn }

// Regression: in an untyped array literal the first concrete element types the array, so a
// following auto-member element (`.Knight`, ...) must resolve against that element's type
// even though there is no outer binding type. Before the fix this raised
// "cannot infer a scope for '.Knight'".
const FirstLine = [PieceKind.Rook, .Knight, .Bishop, .Queen, .King, .Rook]

#assert(#typeof(FirstLine[0]) == PieceKind)
#assert(FirstLine[0] == PieceKind.Rook)
#assert(FirstLine[1] == PieceKind.Knight)
#assert(FirstLine[2] == PieceKind.Bishop)
#assert(FirstLine[5] == PieceKind.Rook)

func semaTest001()
{
    // The same inference must work for a runtime-built array value.
    let pieces = [PieceKind.Queen, .King, .Pawn]
    #assert(#typeof(pieces[0]) == PieceKind)
    @assert(pieces[1] == PieceKind.King)
    @assert(pieces[2] == PieceKind.Pawn)
}
