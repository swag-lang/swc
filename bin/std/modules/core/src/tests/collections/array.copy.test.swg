#global if #command == Swag.CompilerCommand.Test
#global private

// An empty retained allocation copies as an independent empty array, including owning elements.
#test
{
    var source: Array'String
    source.add(String.from("Before clearing"))
    source.clear()
    Swag.assert(source.isEmpty() and source.buffer != null)
    var copy = source
    Swag.assert(copy.isEmpty())
    copy.add(String.from("Copy"))
    source.add(String.from("Source"))
    Swag.assert(copy[0] == "Copy" and source[0] == "Source" and copy.buffer != source.buffer)
}
