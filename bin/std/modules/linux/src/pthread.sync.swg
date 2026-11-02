#global if #os == Swag.TargetOs.Linux
#global export

// Opaque glibc x86-64 mutex storage; initialize it with pthread_mutex_init.
#[Swag.Align(8)]
struct pthread_mutex_t { private storage: [40] u8 }

// Opaque glibc x86-64 condition storage; initialize it with pthread_cond_init.
#[Swag.Align(8)]
struct pthread_cond_t { private storage: [48] u8 }

#assert(#sizeof(pthread_mutex_t) == 40 and #alignof(pthread_mutex_t) == 8)
#assert(#sizeof(pthread_cond_t) == 48 and #alignof(pthread_cond_t) == 8)

// These calls touch only the explicit synchronization objects and do not dispatch callbacks.
// Keep that native contract visible to callers that clear a temporary borrow before returning.
#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C), Swag.BorrowSummary(0, observesExternal: false)]
{
    func pthread_mutex_init(mutex: *pthread_mutex_t, attributes: const *void?)->s32
    func pthread_mutex_destroy(mutex: *pthread_mutex_t)->s32
    func pthread_mutex_lock(mutex: *pthread_mutex_t)->s32
    func pthread_mutex_unlock(mutex: *pthread_mutex_t)->s32
    func pthread_cond_init(condition: *pthread_cond_t, attributes: const *void?)->s32
    func pthread_cond_destroy(condition: *pthread_cond_t)->s32
    func pthread_cond_wait(condition: *pthread_cond_t, mutex: *pthread_mutex_t)->s32
    func pthread_cond_signal(condition: *pthread_cond_t)->s32
    func pthread_cond_broadcast(condition: *pthread_cond_t)->s32
}
