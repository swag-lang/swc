#global fileprivate
#global #if #command == Swag.CompilerCommand.Test

#assert(#typeof(#command) == Swag.CompilerCommand)
#assert(#command == Swag.CompilerCommand.Test)
#assert(#command != Swag.CompilerCommand.Format)
#assert(#command != Swag.CompilerCommand.Build)

