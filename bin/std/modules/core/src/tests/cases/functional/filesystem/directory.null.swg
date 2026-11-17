#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// A null directory request produces no entries without consulting the filesystem.
#test
{
    let entries = expect Directory.enumerate(null, {})
    Swag.require(entries.isEmpty())
}
