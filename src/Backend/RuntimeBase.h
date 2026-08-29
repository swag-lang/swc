#pragma once

// WARNING!
// WARNING! These declarations must be in sync with "bin/runtime/api.swg"
// WARNING!

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    enum class TargetArch
    {
        X86_64,
    };

    enum class TargetOs
    {
        Windows,
    };

    enum class CompilerCommand
    {
        Test,
        Format,
        Build,
    };

    struct TypeInfo;

    struct String
    {
        const char* ptr;
        uint64_t    length;
    };

    template<typename T>
    struct Slice
    {
        T*       ptr;
        uint64_t count;
    };

    struct Any
    {
        void*           value;
        const TypeInfo* type;
    };

    inline constexpr uint32_t CLOSURE_CAPTURE_BUFFER_SIZE = 64;

    struct ClosureValue
    {
        void*   invoke;
        uint8_t capture[CLOSURE_CAPTURE_BUFFER_SIZE];
    };

    enum class ExceptionKind : uint64_t
    {
        Panic   = 0,
        Error   = 1,
        Warning = 2,
        Assert  = 3,
        Safety  = 4,
    };

    enum class RuntimeFlags : uint64_t
    {
        Zero         = 0,
        FromCompiler = 1,
    };

    struct Interface
    {
        void*  obj;
        void** itable;
    };

    struct SourceCodeLocation
    {
        String   fileName;
        String   funcName;
        uint32_t lineStart;
        uint32_t colStart;
        uint32_t lineEnd;
        uint32_t colEnd;
    };

    struct Gvtd
    {
        void* ptr;
        void (*opDrop)(void*);
        uint32_t sizeOf;
        uint32_t count;
    };
}

SWC_END_NAMESPACE();
