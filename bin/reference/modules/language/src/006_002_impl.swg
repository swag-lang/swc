#global private

/**
# Struct Methods and Constants

In Swag, structs can encapsulate methods and constants within them using the 'impl' block.
This keeps related functionality close to the data it operates on.
*/

#[Swag.ExportType(.Methods)]     // Enable method reflection for this struct type
struct MyStruct
{
    x: s32 = 5      // Default 5
    y: s32 = 10     // Default 10
    z: s32 = 20     // Default 20
}

impl MyStruct
{
    const MyConst = true     // Constant in the struct's namespace

    func returnTrue() => true
}

/**
To access the constant or the function, use the 'MyStruct' namespace.
*/
#test
{
    @assert(MyStruct.MyConst)
    @assert(MyStruct.returnTrue())
}

/**
# Multiple 'impl' Blocks

Swag allows multiple 'impl' blocks for the same struct. Inside methods,
'me' refers to the current instance. You can also name the receiver explicitly.
*/

impl MyStruct
{
    // 'me' is implicitly 'var me: MyStruct'
    func returnX(me) => me.x
    func returnY(me) => me.y

    // Explicit receiver name and type
    func returnZ(self: MyStruct) => self.z
}

/**
# Method Syntax Sugar

Using 'mtd' makes the first parameter implicitly 'me'.
Using 'mtd const' makes it 'const me'. This simplifies common patterns.
*/

impl MyStruct
{
    mtd methodReturnX()  => me.x     // Equivalent to 'func methodReturnX(me) => me.x'
    func funcReturnX(me) => me.x
    func funcReturnY(me) => .x     // 'me' can be omitted
}

#test
{
    var c: MyStruct

    @assert(c.returnX() == 5)
    @assert(c.methodReturnX() == 5)
    @assert(c.funcReturnX() == 5)
    @assert(c.returnY() == 10)
    @assert(c.returnZ() == 20)
}

/**
# Method Reflection

To enable reflection on methods in an 'impl' block, annotate the struct with
'#[Swag.ExportType(.Methods)]'. The 'typeinfo' for the struct then exposes
a 'methods' slice. Each 'Swag.TypeValue' supplies the method name, function
type, attributes, and—when callable at runtime—the function pointer.
*/
alias ReflectedMyStructMethod = func(&MyStruct)->s32

#test
{
    let type    = cast(const *Swag.TypeInfoStruct) #type MyStruct
    let methods = notnull type.methods
    var returnX: #null const *Swag.TypeValue

    for &method in methods
    {
        if method.name == "returnX"
        {
            returnX = &method
            break
        }
    }

    @assert(returnX != null)
    let method = notnull returnX
    @assert(method.pointedType!.kind == .Func)

    let call = cast(ReflectedMyStructMethod) notnull method.value
    var value: MyStruct
    @assert(call(&value) == 5)
}
