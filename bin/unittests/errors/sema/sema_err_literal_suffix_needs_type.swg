#global private

const Period = 30_ms     // swc-expected-error {{literal suffix 'ms' needs a target type}}

struct Timer {}

impl Timer
{
    const Offset = -30.0_ms     // swc-expected-error {{literal suffix 'ms' needs a target type}}
}

#test
{
    let period = (30_ms)     // swc-expected-error {{literal suffix 'ms' needs a target type}}
}
