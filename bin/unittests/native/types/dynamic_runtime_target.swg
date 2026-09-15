#global private

#[Swag.DynCast]
struct RuntimeTargetBase { value: s32 = 42 }
struct RuntimeTargetChild { padding: u64; using base: RuntimeTargetBase }
struct RuntimeTargetWrapper { using base: *RuntimeTargetBase }
struct RuntimeTargetGrandchild { using child: RuntimeTargetChild }
struct RuntimeTargetGreatGrandchild { using child: RuntimeTargetGrandchild }
struct RuntimeTargetReadOnly { using child: const *RuntimeTargetChild }
interface IRuntimeTarget { mtd read()->s32 }
impl IRuntimeTarget for RuntimeTargetChild
{
    mtd read()->s32 => .value
}

func compatible(target, source: typeinfo)->bool
{
    return cast #try(target) source != null
}

func compatibleS32(source: typeinfo)->bool       => cast #try(s32) source != null
func compatibleInterface(source: typeinfo)->bool => cast #try(IRuntimeTarget) source != null

alias RuntimeTargetInteger       = s32
#[Swag.Strict]
alias RuntimeTargetStrictInteger = s32
enum RuntimeTargetCode: s32 { Success }

#assert(cast #try(s32) s32 != null)
#assert(cast #try(s64) s32 == null)
#assert(cast #try(s32) RuntimeTargetInteger != null)
#assert(cast #try(s32) RuntimeTargetStrictInteger == null)
#assert(cast #try(RuntimeTargetStrictInteger) RuntimeTargetStrictInteger != null)
#assert(cast #try(s32) RuntimeTargetCode == null)
#assert(cast #try(RuntimeTargetCode) RuntimeTargetCode != null)
#assert(cast #try(*RuntimeTargetBase) #type *RuntimeTargetChild != null)
#assert(cast #try(*RuntimeTargetBase) #type *RuntimeTargetWrapper != null)
#assert(cast #try(*void) #type *RuntimeTargetChild == null)
#assert(cast #try(IRuntimeTarget) RuntimeTargetGreatGrandchild != null)
#assert(cast #try(IRuntimeTarget) RuntimeTargetReadOnly == null)
#assert(cast #try(const IRuntimeTarget) RuntimeTargetReadOnly != null)
#assert(cast #try(*RuntimeTargetBase) #type *RuntimeTargetReadOnly == null)
#assert(cast #try(const *RuntimeTargetBase) #type *RuntimeTargetReadOnly != null)

const RuntimeS32: typeinfo = s32
const RuntimeS64: typeinfo = s64
#assert(cast #try(RuntimeS32) s32 != null)
#assert(cast #try(RuntimeS64) s32 == null)
#assert(cast #try(RuntimeS32) RuntimeS32 != null)
#assert(cast #try(RuntimeS64) RuntimeS32 == null)

#test
{
    Swag.assert(compatible(s32, s32))
    Swag.assert(not compatible(s64, s32))
    Swag.assert(compatible(RuntimeTargetBase, RuntimeTargetChild))
    Swag.assert(compatible(IRuntimeTarget, RuntimeTargetChild))
    Swag.assert(not compatible(RuntimeTargetChild, RuntimeTargetBase))
    Swag.assert(compatible(s32, RuntimeTargetInteger))
    Swag.assert(not compatible(s32, RuntimeTargetStrictInteger))
    Swag.assert(compatible(RuntimeTargetStrictInteger, RuntimeTargetStrictInteger))
    Swag.assert(not compatible(s32, RuntimeTargetCode))
    Swag.assert(compatible(RuntimeTargetCode, RuntimeTargetCode))
    Swag.assert(compatible(#type *RuntimeTargetBase, #type *RuntimeTargetChild))
    Swag.assert(compatible(#type *RuntimeTargetBase, #type *RuntimeTargetWrapper))
    Swag.assert(not compatible(#type *void, #type *RuntimeTargetChild))
    Swag.assert(compatibleS32(s32))
    Swag.assert(not compatibleS32(s64))
    Swag.assert(compatibleInterface(RuntimeTargetChild))
    Swag.assert(not compatibleInterface(RuntimeTargetBase))
    Swag.assert(compatibleInterface(RuntimeTargetGreatGrandchild))
    Swag.assert(not compatibleInterface(RuntimeTargetReadOnly))
    Swag.assert(compatible(#type const IRuntimeTarget, RuntimeTargetReadOnly))
    Swag.assert(not compatible(#type *RuntimeTargetBase, #type *RuntimeTargetReadOnly))
    Swag.assert(compatible(#type const *RuntimeTargetBase, #type *RuntimeTargetReadOnly))
}

func readRuntimeTarget(target: typeinfo, source: any)->s32
{
    let view = cast #try(target) source
    if let object = cast #try(*RuntimeTargetBase) view do
        return object.value
    return -1
}

#test
{
    var value: RuntimeTargetChild
    Swag.assert(readRuntimeTarget(RuntimeTargetBase, &value) == 42)
    Swag.assert(readRuntimeTarget(string, &value) == -1)
    var target: typeinfo = IRuntimeTarget
    let view = cast #try(target) &value
    let itf  = cast #try(IRuntimeTarget) view
    Swag.assert(itf != null)
    Swag.assert(itf.read() == 42)
    target = RuntimeTargetChild
    let child = cast #assume(target) &value.base
    Swag.assert(cast #try(*RuntimeTargetChild) child == &value)
}

#test
{
    var fake = Swag.TypeInfoNative{nativeKind: .S32}
    fake.kind     = .Native
    fake.fullname = "s32"
    fake.name     = "s32"
    fake.sizeof   = 4
    let target: typeinfo = &fake
    var value = 42's32
    Swag.assert(cast #try(target) value == null)
    Swag.assert(not compatible(target, s32))
}

#test
{
    var copy = (cast #assume(const *Swag.TypeInfoNative) s32)[]
    let target: typeinfo = &copy
    Swag.assert(not compatible(target, s32))
    Swag.assert(cast #try(target) 42's32 == null)
}

func runtimeTargetType()->typeinfo => RuntimeTargetBase

#test
{
    var value: RuntimeTargetChild
    let fromCall = cast #try(runtimeTargetType()) &value
    Swag.assert(cast #try(*RuntimeTargetBase) fromCall == &value.base)

    let target: typeinfo = #type const IRuntimeTarget
    let view = cast #try(target) &value
    Swag.assert(view != null)
    Swag.assert(cast #try(const *RuntimeTargetChild) view == &value)
    Swag.assert(cast #try(*RuntimeTargetChild) view == null)
    let itf = cast #try(const IRuntimeTarget) view
    Swag.assert(itf != null)
    Swag.assert(itf.read() == 42)
}
