#global private

const Period = 30'ms     // swc-expected-error {{literal suffix 'ms' needs a target type}}

struct Timer {}

impl Timer
{
    const Offset = -30.0'ms     // swc-expected-error {{literal suffix 'ms' needs a target type}}
}

#test
{
    let period = (30'ms)     // swc-expected-error {{literal suffix 'ms' needs a target type}}
}
