#global private

// 'tls' is meaningful only for a value backed by global storage. It must not
// silently turn a local or a struct field into an ordinary variable.

func tlsLocal()
{
    tls var value: u32     // swc-expected-error {{sema_err_tls_not_global}}
}

struct TlsField
{
    tls value: u32     // swc-expected-error {{sema_err_tls_not_global}}
}
