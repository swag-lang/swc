#global private

// A 'tls' block is released by the thread-exit destructor, which frees bytes without
// knowing their type. A value with a drop lifecycle would leak once per thread, so the
// combination is refused at the declaration.

struct TlsOwned
{
    handle: *void?
}

impl TlsOwned
{
    mtd opDrop() { .handle = null }
}

struct TlsHolder
{
    owned: TlsOwned
}

tls var tlsOwned: TlsOwned     // swc-expected-error {{sema_err_tls_global_with_drop}}

tls var tlsHolder: TlsHolder     // swc-expected-error {{sema_err_tls_global_with_drop}}

tls var tlsOwnedArray: [4] TlsOwned     // swc-expected-error {{sema_err_tls_global_with_drop}}

// A plain value type stays legal.
tls var tlsCounter: u64
