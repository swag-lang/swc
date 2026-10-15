namespace Swag
{
    // #########################################################
    // Process
    // #########################################################

    // Describes a loaded module.
    struct Module
    {
        public
        {
            name:  string?     // Name of the module
            types: const [..] (const *TypeInfo?)?     // All exported types
        }
    }

    // Describes the current process, as returned by [[Swag.processInfo]].
    struct ProcessInfo
    {
        public
        {
            modules: const [..] Module?     // Every loaded module
            args:    string?     // The application arguments, as returned by [[Swag.args]].
        }
    }

    // Describes a global variable that the runtime drops when the process exits.
    struct GlobalToDrop
    {
        public
        {
            ptr:    *void            // Pointer to the global variable memory
            opDrop: func(*void?)     // The 'opDrop' function to call when the process must exit
            sizeOf: u32              // Size of one element
            count:  u32              // Number of elements to drop
        }
    }

    // #########################################################
    // Allocators
    // #########################################################

    // Carries the operands of one [[IAllocator]] operation.
    //
    // The operation itself is the method being called; the request only transports its
    // operands and the tracking metadata.
    //
    // For [[IAllocator.alloc]]:
    // - 'size' must be the size in bytes to allocate
    // - 'alignment' must be the alignment constraint in bytes (or 0)
    // - 'address' will be the returned allocated memory address
    //
    // For [[IAllocator.free]]:
    // - 'size' must be the original allocated size in bytes of 'address'
    // - 'address' must be the memory address to release
    //
    // For [[IAllocator.realloc]]:
    // - 'size' must be the new size in bytes
    // - 'oldSize' must be the original allocated size in bytes of 'address'
    // - 'address' must be the memory address to reallocate, and receives the new one
    //
    // See [[IAllocator]]
    struct AllocatorRequest
    {
        public
        {
            callerLoc: SourceCodeLocation     // Location of the caller, to help track leaks; optional
            hint:      string?     // Message to help track leaks; optional
            address:   *void?      // Address to operate on, or the address returned
            size:      u64         // Size requested or operated on, in bytes
            oldSize:   u64         // Previous size of a reallocated block, in bytes
            alignment: u32         // Alignment constraint in bytes, or 0
        }
    }

    // Allocates, reallocates, and frees memory.
    //
    // Every operation is a distinct method so the semantics are structural: the compiler's
    // static lifetime analysis and the reader both know what a call does without inspecting
    // the request.
    interface IAllocator
    {
        // Allocates a block of memory and stores its address in 'request.address'.
        mtd alloc(request: *AllocatorRequest)

        // Resizes a block allocated by this allocator, possibly moving it.
        mtd realloc(request: *AllocatorRequest)

        // Frees a block allocated by this allocator.
        mtd free(request: *AllocatorRequest)

        // Frees every block allocated with this allocator at once.
        //
        // An allocator that cannot release its blocks together keeps this default, which frees
        // nothing: each block stays allocated until it is freed on its own.
        mtd freeAll(_: *AllocatorRequest) {}

        // Asserts that 'request.address' is a block this allocator currently owns.
        //
        // An allocator that does not track its blocks keeps this default, which checks nothing.
        mtd assertAllocated(_: *AllocatorRequest) {}
    }

    // A linear allocator that acquires its buffer on first use and releases all blocks at once.
    //
    // Its bookkeeping is readable everywhere and written only by its own operations.
    struct ScratchAllocator
    {
        public readonly
        {
            allocator: IAllocator?     // Where the buffer and the blocks that do not fit come from
            block:     [*] u8?         // The buffer, once acquired
            capacity:  u64             // Size of the buffer, in bytes
            used:      u64             // Bytes of the buffer in use
            maxUsed:   u64             // Most bytes of the buffer ever in use
            firstLeak: *void?          // First block that did not fit in the buffer
            totalLeak: u64             // Bytes held by the blocks that did not fit
            maxLeak:   u64             // Most bytes ever held by the blocks that did not fit
        }

        // An internal owner can retain the backing storage beyond this allocator's release.
        releaseOwner: *void?
        releaseHook:  (func(*ScratchAllocator))?
    }

    // #########################################################
    // Context
    // #########################################################

    // What raised an exception.
    enum ExceptionKind
    {
        Panic
        Error
        Warning
        Assert
        Safety
    }

    const MaxTraces = 32     // Maximum error traces

    // The base of every error raised with 'fail'.
    struct BaseError
    {
        public message: string?
    }

    // An error reported by the operating system, with its native error code.
    struct SystemError
    {
        public
        {
            using base: Swag.BaseError
            errorID:    u64     // The host's own error code: 'GetLastError' on Windows
        }
    }

    // One level of the error stack of a [[Context]].
    struct ErrorValue
    {
        public value: any?     // Error value (or null)

        record: *ErrorRecord?     // Owner of the dynamically typed payload.

        // What the error stack must restore when this entry is popped. The runtime writes it
        // when an error is pushed and reads it back on 'catch'.
        reserved:           u32
        pushTraceIndex:     u32     // Stack-trace depth at the push.
        pushHasError:       u32     // Whether an error was already pending at the push.
        padding:            u32
        pushCurError:       any?     // Current handled error at the push.
        pushErrorAllocator: ScratchAllocator     // Parent message storage while this frame runs.
    }

    // Number of error stack levels a [[Context]] holds itself. Handlers seldom nest deeper, so
    // ordinary code never allocates for its error stack.
    #[NoDoc]
    const ErrorInlineCount = 4'u32

    // Number of error stack levels a block of a [[Context]] holds above its own.
    #[NoDoc]
    const ErrorBlockCount = 16'u32

    // A block of the error stack of a [[Context]], above the levels the context holds itself.
    //
    // The stack grows a block at a time as handlers nest, so its depth has no fixed limit.
    // A block never moves once allocated: a context copied for the length of a scope shares the
    // blocks of the context it was copied from, and only uses the levels above the ones in use.
    #[NoDoc]
    struct ErrorBlock
    {
        next:      *ErrorBlock?
        allocator: IAllocator     // Where the block comes from, and goes back to.
        values:    [ErrorBlockCount] ErrorValue
    }

    // Per-thread state, as returned by [[Swag.getContext]].
    struct Context
    {
        public
        {
            // Must stay first, in that order, for backend generation

            allocator: IAllocator?     // The current allocator interface

            // Other fields, can be in any order

            tempAllocator:    ScratchAllocator     // A temporary allocator for the user
            errorAllocator:   ScratchAllocator     // Copied error messages for the current handled operation.
            runtimeFlags:     RuntimeFlags         // As initialized by the runtime
            defaultAllocator: IAllocator?          // The default allocator, to restore after a temporary change of 'allocator'
            user0:            u64                  // For user usage
            user1:            u64                  // For user usage
            user2:            u64                  // For user usage
            user3:            u64                  // For user usage
            traces:           [MaxTraces] SourceCodeLocation     // Stack trace, in case of errors
            #[Swag.NoDoc]
            errorLevels: [ErrorInlineCount] ErrorValue     // The first levels of the error stack.
            #[Swag.NoDoc]
            errorBlocks:     *ErrorBlock?           // The levels above them, allocated on first use.
            exceptionLoc:    SourceCodeLocation     // When an exception is raised, this is the code location
            exceptionParams: [4] (const *void?)     // When an exception is raised, these are its parameters
            panic:           (func(string?, SourceCodeLocation))?     // A function to call if there's a panic
            curError:        any?                   // The current raised error
            errorIndex:      u32                    // Number of error stack levels in use
            traceIndex:      u32                    // Number of traces in the array
            hasError:        u32                    // Nonzero while an error is raised
            #[Swag.NoDoc]
            errorCaptures: *ErrorCapture?     // Live lexical owners of caught errors.
            #[Swag.NoDoc]
            runtimeTlsIdPlusOne: u64     // Process TLS slot shared by dynamically loaded Swag modules.
            #[Swag.NoDoc]
            panicStack: [64] (*void?)     // Native call stack captured before entering a panic hook.
            #[Swag.NoDoc]
            panicStackCount: u32     // Number of valid addresses in panicStack.
            #[Swag.NoDoc]
            panicCatch: *void?     // Innermost 'catchPanic' running on this context.
            #[Swag.NoDoc]
            cancelScope: *CancelScope?     // Cancellation state of the work running on this context.
        }
    }

    // Represent a part of a source code file.
    //
    // This is typically what will be returned by '#curlocation' or '#callerlocation'.
    struct SourceCodeLocation
    {
        public
        {
            fileName:  string?     // Full path name of the source file
            funcName:  string?     // Name of the function
            lineStart: u32         // Start line (starts at 0)
            colStart:  u32         // Start column
            lineEnd:   u32         // End line
            colEnd:    u32         // End column
        }
    }
}
