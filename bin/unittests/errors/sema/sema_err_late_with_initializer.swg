#global private

struct LateInitializer
{
    late value: string = "already set"     // swc-expected-error {{sema_err_late_with_initializer}}
}
