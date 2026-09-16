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
    return source is target
}

func compatibleS32(source: typeinfo)->bool       => source is s32
func compatibleInterface(source: typeinfo)->bool => source is IRuntimeTarget

alias RuntimeTargetInteger       = s32
#[Swag.Strict]
alias RuntimeTargetStrictInteger = s32
enum RuntimeTargetCode: s32 { Success }

#assert(s32 is s32)
#assert(not (s32 is s64))
#assert(RuntimeTargetInteger is s32)
#assert(not (RuntimeTargetStrictInteger is s32))
#assert(RuntimeTargetStrictInteger is RuntimeTargetStrictInteger)
#assert(not (RuntimeTargetCode is s32))
#assert(RuntimeTargetCode is RuntimeTargetCode)
#assert(#type *RuntimeTargetChild is *RuntimeTargetBase)
#assert(#type *RuntimeTargetWrapper is *RuntimeTargetBase)
#assert(not (#type *RuntimeTargetChild is *void))
#assert(RuntimeTargetGreatGrandchild is IRuntimeTarget)
#assert(not (RuntimeTargetReadOnly is IRuntimeTarget))
#assert(RuntimeTargetReadOnly is const IRuntimeTarget)
#assert(not (#type *RuntimeTargetReadOnly is *RuntimeTargetBase))
#assert(#type *RuntimeTargetReadOnly is const *RuntimeTargetBase)

const RuntimeS32: typeinfo = s32
const RuntimeS64: typeinfo = s64
#assert(s32 is RuntimeS32)
#assert(not (s32 is RuntimeS64))
#assert(RuntimeS32 is RuntimeS32)
#assert(not (RuntimeS32 is RuntimeS64))

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
    if view is RuntimeTargetBase as object do
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
    var value            = 42's32
    let castResult1      = cast #try(target) value
    Swag.assert(castResult1 == null)
    Swag.assert(not compatible(target, s32))
}

#test
{
    var copy = (cast #assume(const *Swag.TypeInfoNative) s32)[]
    let target: typeinfo = &copy
    Swag.assert(not compatible(target, s32))
    let castResult2 = cast #try(target) 42's32
    Swag.assert(castResult2 == null)
}

func runtimeTargetType()->typeinfo => RuntimeTargetBase

#test
{
    var value: RuntimeTargetChild
    Swag.assert(&value is runtimeTargetType())
    Swag.assert(RuntimeTargetChild is runtimeTargetType())
    var zero = 0's32
    let integerTarget: typeinfo = s32
    Swag.assert(&zero is integerTarget)
    var falseValue = false
    let boolTarget: typeinfo = bool
    Swag.assert(&falseValue is boolTarget)
    Swag.assert(not (cast #assume(bool) (cast #try(boolTarget) &falseValue)))
    let fromCall = cast #try(runtimeTargetType()) &value
    Swag.assert(cast #try(*RuntimeTargetBase) fromCall == &value.base)

    let target: typeinfo = #type const IRuntimeTarget
    let view = cast #try(target) &value
    Swag.assert(view != null)
    Swag.assert(cast #try(const *RuntimeTargetChild) view == &value)
    let castResult3 = cast #try(*RuntimeTargetChild) view
    Swag.assert(castResult3 == null)
    let itf = cast #try(const IRuntimeTarget) view
    Swag.assert(itf != null)
    Swag.assert(itf.read() == 42)
}
