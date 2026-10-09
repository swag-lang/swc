#global private

// An 'impl <Interface> for <Struct>' block that leaves out a method the interface gives no
// default body for is reported against that block, and names the missing method.

interface IMissingShape
{
    mtd area()->f32
    mtd name()->string => "shape"
}

struct MissingSquare
{
    side: f32
}

impl IMissingShape for MissingSquare {}     // swc-expected-error {{sema_err_interface_method_not_implemented}}

#test
{
    var square: MissingSquare
    let shape = cast(IMissingShape, square)
    Swag.assert(shape.area() == 0)
}
