#global private

struct LateInitializer
{
    value: #late string = "already set" // swc-expected-error {{sema_err_late_with_initializer}}
}
