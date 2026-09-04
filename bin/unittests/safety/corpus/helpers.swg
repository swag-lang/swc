#global namespace Corpus

using Swag

// -----------------------------------------------------------------------------
// Shared support for the CWE corpus.
//
// Every helper here exists for one reason: to defeat constant folding, so a case meant for
// a RUNTIME guard is not answered by the static analysis instead, and the reverse. A corpus
// that cannot say which layer caught a fault measures nothing.
// -----------------------------------------------------------------------------

// Launders a value through a call the optimizer must not see into.
#[Swag.NoInline]
func opaqueU64(v: u64)->u64 => v

#[Swag.NoInline]
func opaqueS64(v: s64)->s64 => v

#[Swag.NoInline]
func opaqueS32(v: s32)->s32 => v

#[Swag.NoInline]
func opaqueU32(v: u32)->u32 => v

#[Swag.NoInline]
func opaqueS8(v: s8)->s8 => v

#[Swag.NoInline]
func opaqueU8(v: u8)->u8 => v

#[Swag.NoInline]
func opaqueS16(v: s16)->s16 => v

#[Swag.NoInline]
func opaqueF32(v: f32)->f32 => v

#[Swag.NoInline]
func opaqueBool(v: bool)->bool => v

// -----------------------------------------------------------------------------
// The heap, reached through the language interface rather than through a standard module:
// the corpus exercises what the LANGUAGE knows, not what a name in 'std' happens to be
// called. These two are what seed the FREES summary the lifetime analysis reads.
// -----------------------------------------------------------------------------

// '#[Swag.NoInline]' is a WORKAROUND for compiler.core.029, not part of the contract: in
// 'release', inlining this across a file boundary into a struct-field assignment trips a
// compiler assertion. Remove it when that entry closes.
#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func heapAlloc(size: u64)->*void
{
    var req: AllocatorRequest
    req.size = size
    let itf = Swag.getContext().allocator!
    itf.alloc(&req)
    return req.address!
}

#[Swag.Sanity(.Lifecycle, true)]
func heapFree(ptr: *void, size: u64)
{
    var req: AllocatorRequest
    req.address = ptr
    req.size    = size
    let itf = Swag.getContext().allocator!
    itf.free(&req)
}
