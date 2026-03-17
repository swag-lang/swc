#global fileprivate // swc-option sema-only

func add(x: s32, y: bool)->f32 => 1.0
func consume(value: string) {}

#assert((cast(const *Swag.TypeInfoFunc) #typeof(add)).name == "func(x: s32, y: bool)->f32")

const ADD = cast(const *Swag.TypeInfoFunc) #typeof(add)
#assert(@countof(ADD.parameters) == 2)
#assert(ADD.parameters[0].name == "x")
#assert(ADD.parameters[1].name == "y")
#assert(ADD.parameters[0].pointedType == s32)
#assert(ADD.parameters[1].pointedType == bool)
#assert(ADD.returnType == f32)

const CONSUME = cast(const *Swag.TypeInfoFunc) #typeof(consume)
#assert(@countof(CONSUME.parameters) == 1)
#assert(CONSUME.parameters[0].name == "value")
#assert(CONSUME.parameters[0].pointedType == string)

#test
{
    let typeFunc = cast(const *Swag.TypeInfoFunc) #typeof(add)
    let ok       = typeFunc.parameters[0].pointedType == s32 and typeFunc.returnType == f32
}
