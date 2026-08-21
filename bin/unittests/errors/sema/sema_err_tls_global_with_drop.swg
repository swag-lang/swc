#global private

// A '#[Swag.Tls]' block is released by the thread-exit destructor, which frees bytes without
// knowing their type. A value with a drop lifecycle would leak once per thread, so the
// combination is refused at the declaration.

struct TlsOwned
{
    handle: #null *void
}

impl TlsOwned
{
    mtd opDrop() { .handle = null }
}

struct TlsHolder
{
    owned: TlsOwned
}

#[Swag.Tls]
var tlsOwned: TlsOwned     // swc-expected-error {{sema_err_tls_global_with_drop}}

#[Swag.Tls]
var tlsHolder: TlsHolder     // swc-expected-error {{sema_err_tls_global_with_drop}}

#[Swag.Tls]
var tlsOwnedArray: [4] TlsOwned     // swc-expected-error {{sema_err_tls_global_with_drop}}

// A plain value type stays legal.
#[Swag.Tls]
var tlsCounter: u64
