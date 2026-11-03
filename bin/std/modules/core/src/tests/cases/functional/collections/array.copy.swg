#global if #command == Swag.CompilerCommand.Test
#global private

// An empty retained allocation copies as an independent empty array, including owning elements.
#test
{
    var source: Array'String
    source.add(String.from("Before clearing"))
    source.clear()
    Swag.require(source.isEmpty() and source.buffer != null)
    var copy = source
    Swag.require(copy.isEmpty())
    copy.add(String.from("Copy"))
    source.add(String.from("Source"))
    Swag.require(copy[0] == "Copy" and source[0] == "Source" and copy.buffer != source.buffer)
}
