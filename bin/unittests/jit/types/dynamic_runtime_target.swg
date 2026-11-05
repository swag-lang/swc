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
    Swag.require(compatible(s32, s32))
    Swag.require(not compatible(s64, s32))
    Swag.require(compatible(RuntimeTargetBase, RuntimeTargetChild))
    Swag.require(compatible(IRuntimeTarget, RuntimeTargetChild))
    Swag.require(not compatible(RuntimeTargetChild, RuntimeTargetBase))
    Swag.require(compatible(s32, RuntimeTargetInteger))
    Swag.require(not compatible(s32, RuntimeTargetStrictInteger))
    Swag.require(compatible(RuntimeTargetStrictInteger, RuntimeTargetStrictInteger))
    Swag.require(not compatible(s32, RuntimeTargetCode))
    Swag.require(compatible(RuntimeTargetCode, RuntimeTargetCode))
    Swag.require(compatible(#type *RuntimeTargetBase, #type *RuntimeTargetChild))
    Swag.require(compatible(#type *RuntimeTargetBase, #type *RuntimeTargetWrapper))
    Swag.require(not compatible(#type *void, #type *RuntimeTargetChild))
    Swag.require(compatibleS32(s32))
    Swag.require(not compatibleS32(s64))
    Swag.require(compatibleInterface(RuntimeTargetChild))
    Swag.require(not compatibleInterface(RuntimeTargetBase))
    Swag.require(compatibleInterface(RuntimeTargetGreatGrandchild))
    Swag.require(not compatibleInterface(RuntimeTargetReadOnly))
    Swag.require(compatible(#type const IRuntimeTarget, RuntimeTargetReadOnly))
    Swag.require(not compatible(#type *RuntimeTargetBase, #type *RuntimeTargetReadOnly))
    Swag.require(compatible(#type const *RuntimeTargetBase, #type *RuntimeTargetReadOnly))
}

func readRuntimeTarget(target: typeinfo, source: any)->s32
{
    let view = catch cast(any?, cast(target, source))
    if view is RuntimeTargetBase as object do
        return object.value
    return -1
}

#test
{
    var value: RuntimeTargetChild
    Swag.require(readRuntimeTarget(RuntimeTargetBase, &value) == 42)
    Swag.require(readRuntimeTarget(string, &value) == -1)
    var target: typeinfo = IRuntimeTarget
    let view = catch cast(any?, cast(target, &value))
    let itf  = catch cast(IRuntimeTarget?, view)
    Swag.require(itf != null)
    Swag.require(itf.read() == 42)
    target = RuntimeTargetChild
    let child = assume cast(target, &value.base)
    Swag.require((catch cast(*RuntimeTargetChild?, child)) == &value)
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
    let castResult1      = catch cast(any?, cast(target, value))
    Swag.require(castResult1 == null)
    Swag.require(not compatible(target, s32))
}

#test
{
    var copy = assume cast(const *Swag.TypeInfoNative, s32)[]
    let target: typeinfo = &copy
    Swag.require(not compatible(target, s32))
    let castResult2 = catch cast(const any?, cast(target, 42's32))
    Swag.require(castResult2 == null)
}

func runtimeTargetType()->typeinfo => RuntimeTargetBase

#test
{
    var value: RuntimeTargetChild
    Swag.require(&value is runtimeTargetType())
    Swag.require(RuntimeTargetChild is runtimeTargetType())
    var zero = 0's32
    let integerTarget: typeinfo = s32
    Swag.require(&zero is integerTarget)
    var falseValue = false
    let boolTarget: typeinfo = bool
    Swag.require(&falseValue is boolTarget)
    Swag.require(not assume cast(bool, (catch cast(any?, cast(boolTarget, &falseValue)))))
    let fromCall = catch cast(any?, cast(runtimeTargetType(), &value))
    Swag.require((catch cast(*RuntimeTargetBase?, fromCall)) == &value.base)

    let target: typeinfo = #type const IRuntimeTarget
    let view = catch cast(any?, cast(target, &value))
    Swag.require(view != null)
    Swag.require((catch cast(const *RuntimeTargetChild?, view)) == &value)
    let castResult3 = catch cast(*RuntimeTargetChild?, view)
    Swag.require(castResult3 == null)
    let itf = catch cast(const IRuntimeTarget?, view)
    Swag.require(itf != null)
    Swag.require(itf.read() == 42)
}
