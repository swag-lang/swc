#global private

struct Source {x, y: s32}
struct Target {x, y, z: s32}
struct Excess {x, y, z, w: s32}

func accept(value: Target) { discard value }
func accept(value: *s32) { discard value }

#test
{
    // swc-expected-error@+3 {{sema_err_no_overload_match}}
    // swc-expected-note@+2 {{cannot cast from 'Source' to 'Target'; source provides 2 fields, destination needs 3}}
    // swc-expected-note@+1 {{parameter 'value' needs '*s32', but argument 1 has type 'Source'}}
    accept(Source{})
}

#test
{
    // swc-expected-note@+1 {{cannot cast from 'Excess' to 'Target'; source provides 4 fields, destination needs 3}}
    accept(Excess{})     // swc-expected-error {{sema_err_no_overload_match}}
}
