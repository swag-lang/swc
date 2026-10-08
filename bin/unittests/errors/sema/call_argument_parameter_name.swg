#global private

// A call argument that does not fit names the parameter it was given to. The receiver of
// a method is the parameter 'me', declared or not, and a function value names itself as
// the callee: the source token at the report site is an argument, never a parameter.

interface IParameterName
{
    mtd setup(count: s32)
}

struct ParameterNameOwner
{
    count: s32
}

struct ParameterNameThing
{
    count: s32
}

impl IParameterName for ParameterNameThing
{
    mtd impl setup(count: s32) { .count = count }
}

impl ParameterNameThing
{
    mtd add(amount: s32) { .count += amount }
}

func parameterNameQualified(owner: *ParameterNameOwner)
{
    ParameterNameThing.IParameterName.setup(owner, 1)     // swc-expected-error {{argument 1 for call to 'setup' has type '*ParameterNameOwner', but parameter 'me' needs '*ParameterNameThing'}}
}

func parameterNameMethod(owner: *ParameterNameOwner)
{
    ParameterNameThing.add(owner, 1)     // swc-expected-error {{argument 1 for call to 'add' has type '*ParameterNameOwner', but parameter 'me' needs '*ParameterNameThing'}}
}

func parameterNameUnnamed(callback: func(s32), wide: u64)
{
    callback(wide)     // swc-expected-error {{argument 1 for call to 'callback' has type 'u64', but the parameter needs 's32'}}
}
