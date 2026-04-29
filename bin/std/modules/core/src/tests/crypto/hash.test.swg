#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    @assert(Hash.Md5.toString(Hash.Md5.compute("")) == "D41D8CD98F00B204E9800998ECF8427E")
    @assert(Hash.Md5.toString(Hash.Md5.compute("abc")) == "900150983CD24FB0D6963F7D28E17F72")

}
