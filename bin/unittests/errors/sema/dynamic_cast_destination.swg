#global private

func valueDestination(value: any)
{
    // swc-expected-error@(+1) {{'cast #try' cannot return null for destination 's32'}}
    discard cast #try (s32) value
}
