#include "pch.h"
#include "Backend/FFI/FFI.h"
#include "Backend/MachineCode/CallConv.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Core/SmallVector.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST
#ifdef _M_X64

namespace
{
    SymbolVariable* makeStructField(TaskContext& ctx, TypeRef typeRef)
    {
        auto* field = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        field->setTypeRef(typeRef);
        return field;
    }

    TypeRef makeStructType(TaskContext& ctx, std::span<const TypeRef> fieldTypes)
    {
        auto* symStruct = Symbol::make<SymbolStruct>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        for (const auto fieldType : fieldTypes)
            symStruct->addField(makeStructField(ctx, fieldType));
        SWC_ASSERT(symStruct->computeLayout(ctx) == Result::Continue);

        const TypeRef structTypeRef = ctx.typeMgr().addType(TypeInfo::makeStruct(symStruct));
        symStruct->setTypeRef(structTypeRef);
        return structTypeRef;
    }

    Result callCaseTyped(TaskContext& ctx, void* targetFn, std::span<const FFIArgument> args, TypeRef retTypeRef, void* outRetValue)
    {
        FFI::callFFI(ctx, targetFn, args, {.typeRef = retTypeRef, .valuePtr = outRetValue});
        return Result::Continue;
    }
}

namespace
{
    struct FFIStructPair32
    {
        uint32_t a;
        uint32_t b;
    };

    struct FFIStructTriple64
    {
        uint64_t a;
        uint64_t b;
        uint64_t c;
    };

    bool ffiNativeReturnTrue()
    {
        return true;
    }

    uint8_t ffiNativeAddU8(uint8_t a, uint8_t b)
    {
        return static_cast<uint8_t>(a + b);
    }

    int32_t ffiNativeAddI32(int32_t a, int32_t b)
    {
        return a + b;
    }

    float ffiNativeAddF32(float a, float b)
    {
        return a + b;
    }

    double ffiNativeAddF64(double a, double b)
    {
        return a + b;
    }

    double ffiNativeSum5F64(double a, double b, double c, double d, double e)
    {
        return a + b + c + d + e;
    }

    uint64_t ffiNativeMixArgs(uint8_t a, uint16_t b, uint32_t c, uint64_t d)
    {
        return static_cast<uint64_t>(a) + static_cast<uint64_t>(b) + static_cast<uint64_t>(c) + d;
    }

    int64_t ffiNativeStackArgs(int64_t a, int64_t b, int64_t c, int64_t d, int64_t e, int64_t f)
    {
        return a + b + c + d + e + f;
    }

    bool ffiNativeConsumePtr(const void* ptr)
    {
        return ptr != nullptr;
    }

    uint64_t ffiNativeStructPair32Sum(FFIStructPair32 value)
    {
        return static_cast<uint64_t>(value.a) + value.b;
    }

    uint64_t ffiNativeStructPair32Stack(uint64_t a, uint64_t b, uint64_t c, uint64_t d, FFIStructPair32 value)
    {
        return a + b + c + d + value.a + value.b;
    }

    uint64_t ffiNativeStructTriple64Mutate(FFIStructTriple64 value)
    {
        value.a += 5;
        return value.a + value.b + value.c;
    }

    FFIStructPair32 ffiNativeReturnStructPair32(uint32_t a, uint32_t b)
    {
        return {.a = a, .b = b};
    }

    FFIStructTriple64 ffiNativeReturnStructTriple64(uint64_t seed)
    {
        return {.a = seed + 1, .b = seed + 2, .c = seed + 3};
    }

}

SWC_TEST_BEGIN(FFI_CallNativeNoArgBool)
{
    const auto& typeMgr = ctx.typeMgr();
    bool        result  = false;
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeReturnTrue), std::span<const FFIArgument>{}, typeMgr.typeBool(), &result));
    if (!result)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeU8)
{
    const auto& typeMgr = ctx.typeMgr();

    constexpr uint8_t a = 19;
    constexpr uint8_t b = 23;

    const SmallVector<FFIArgument> args = {
        {.typeRef = typeMgr.typeU8(), .valuePtr = &a},
        {.typeRef = typeMgr.typeU8(), .valuePtr = &b},
    };

    uint8_t result = 0;
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeAddU8), args, typeMgr.typeU8(), &result));
    if (result != 42)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeI32)
{
    const auto& typeMgr = ctx.typeMgr();

    constexpr int32_t a = -1200;
    constexpr int32_t b = -137;

    const SmallVector<FFIArgument> args = {
        {.typeRef = typeMgr.typeS32(), .valuePtr = &a},
        {.typeRef = typeMgr.typeS32(), .valuePtr = &b},
    };

    int32_t result = 0;
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeAddI32), args, typeMgr.typeS32(), &result));
    if (result != -1337)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeF32)
{
    const auto& typeMgr = ctx.typeMgr();

    constexpr float a = 0.5f;
    constexpr float b = 1.25f;

    const SmallVector<FFIArgument> args = {
        {.typeRef = typeMgr.typeF32(), .valuePtr = &a},
        {.typeRef = typeMgr.typeF32(), .valuePtr = &b},
    };

    float result = 0;
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeAddF32), args, typeMgr.typeF32(), &result));
    if (result != 1.75f)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeF64)
{
    const auto& typeMgr = ctx.typeMgr();

    constexpr double a = 1.5;
    constexpr double b = 2.5;

    const SmallVector<FFIArgument> args = {
        {.typeRef = typeMgr.typeF64(), .valuePtr = &a},
        {.typeRef = typeMgr.typeF64(), .valuePtr = &b},
    };

    double result = 0;
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeAddF64), args, typeMgr.typeF64(), &result));
    if (result != 4.0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeF64StackArg)
{
    const auto& typeMgr = ctx.typeMgr();

    constexpr double a = 1.0;
    constexpr double b = 2.0;
    constexpr double c = 3.0;
    constexpr double d = 4.0;
    constexpr double e = 5.0;

    const SmallVector<FFIArgument> args = {
        {.typeRef = typeMgr.typeF64(), .valuePtr = &a},
        {.typeRef = typeMgr.typeF64(), .valuePtr = &b},
        {.typeRef = typeMgr.typeF64(), .valuePtr = &c},
        {.typeRef = typeMgr.typeF64(), .valuePtr = &d},
        {.typeRef = typeMgr.typeF64(), .valuePtr = &e},
    };

    double result = 0;
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeSum5F64), args, typeMgr.typeF64(), &result));
    if (result != 15.0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeMixedArgs)
{
    const auto& typeMgr = ctx.typeMgr();

    constexpr uint8_t  a = 1;
    constexpr uint16_t b = 2;
    constexpr uint32_t c = 70000;
    constexpr uint64_t d = 0;

    const SmallVector<FFIArgument> args = {
        {.typeRef = typeMgr.typeU8(), .valuePtr = &a},
        {.typeRef = typeMgr.typeU16(), .valuePtr = &b},
        {.typeRef = typeMgr.typeU32(), .valuePtr = &c},
        {.typeRef = typeMgr.typeU64(), .valuePtr = &d},
    };

    uint64_t result = 0;
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeMixArgs), args, typeMgr.typeU64(), &result));
    if (result != 70003ULL)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeStackArgs)
{
    const auto& typeMgr = ctx.typeMgr();

    constexpr int64_t a = 1;
    constexpr int64_t b = 2;
    constexpr int64_t c = 3;
    constexpr int64_t d = 4;
    constexpr int64_t e = 5;
    constexpr int64_t f = 6;

    const SmallVector<FFIArgument> args = {
        {.typeRef = typeMgr.typeS64(), .valuePtr = &a},
        {.typeRef = typeMgr.typeS64(), .valuePtr = &b},
        {.typeRef = typeMgr.typeS64(), .valuePtr = &c},
        {.typeRef = typeMgr.typeS64(), .valuePtr = &d},
        {.typeRef = typeMgr.typeS64(), .valuePtr = &e},
        {.typeRef = typeMgr.typeS64(), .valuePtr = &f},
    };

    int64_t result = 0;
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeStackArgs), args, typeMgr.typeS64(), &result));
    if (result != 21)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativePointerArg)
{
    const auto& typeMgr = ctx.typeMgr();

    const void* ptr = reinterpret_cast<void*>(0x10);

    const SmallVector<FFIArgument> args = {
        {.typeRef = typeMgr.typeConstValuePtrVoid(), .valuePtr = &ptr},
    };

    bool result = false;
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeConsumePtr), args, typeMgr.typeBool(), &result));
    if (!result)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeStructByValueRegister)
{
    if (CallConv::host().classifyStructArgPassing(sizeof(FFIStructPair32)) != StructArgPassingKind::ByValue)
        return Result::Continue;

    const auto& typeMgr = ctx.typeMgr();

    const std::array fieldTypes = {
        typeMgr.typeU32(),
        typeMgr.typeU32(),
    };
    const TypeRef structTypeRef = makeStructType(ctx, fieldTypes);

    constexpr FFIStructPair32      value = {.a = 18, .b = 24};
    const SmallVector<FFIArgument> args  = {
        {.typeRef = structTypeRef, .valuePtr = &value},
    };

    uint64_t result = 0;
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeStructPair32Sum), args, typeMgr.typeU64(), &result));
    if (result != 42)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeStructByValueStack)
{
    if (CallConv::host().classifyStructArgPassing(sizeof(FFIStructPair32)) != StructArgPassingKind::ByValue)
        return Result::Continue;

    const auto& typeMgr = ctx.typeMgr();

    const std::array fieldTypes = {
        typeMgr.typeU32(),
        typeMgr.typeU32(),
    };
    const TypeRef structTypeRef = makeStructType(ctx, fieldTypes);

    constexpr uint64_t        a     = 1;
    constexpr uint64_t        b     = 2;
    constexpr uint64_t        c     = 3;
    constexpr uint64_t        d     = 4;
    constexpr FFIStructPair32 value = {.a = 10, .b = 20};

    const SmallVector<FFIArgument> args = {
        {.typeRef = typeMgr.typeU64(), .valuePtr = &a},
        {.typeRef = typeMgr.typeU64(), .valuePtr = &b},
        {.typeRef = typeMgr.typeU64(), .valuePtr = &c},
        {.typeRef = typeMgr.typeU64(), .valuePtr = &d},
        {.typeRef = structTypeRef, .valuePtr = &value},
    };

    uint64_t result = 0;
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeStructPair32Stack), args, typeMgr.typeU64(), &result));
    if (result != 40)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeStructByReferenceCopy)
{
    if (CallConv::host().classifyStructArgPassing(sizeof(FFIStructTriple64)) != StructArgPassingKind::ByReference)
        return Result::Continue;

    const auto& typeMgr = ctx.typeMgr();

    const std::array fieldTypes = {
        typeMgr.typeU64(),
        typeMgr.typeU64(),
        typeMgr.typeU64(),
    };
    const TypeRef structTypeRef = makeStructType(ctx, fieldTypes);

    FFIStructTriple64              value = {.a = 10, .b = 20, .c = 30};
    const SmallVector<FFIArgument> args  = {
        {.typeRef = structTypeRef, .valuePtr = &value},
    };

    uint64_t result = 0;
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeStructTriple64Mutate), args, typeMgr.typeU64(), &result));
    if (result != 65)
        return Result::Error;
    if (value.a != 10 || value.b != 20 || value.c != 30)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeStructReturnByValueRegister)
{
    if (CallConv::host().classifyStructReturnPassing(sizeof(FFIStructPair32)) != StructArgPassingKind::ByValue)
        return Result::Continue;

    const auto& typeMgr = ctx.typeMgr();

    const std::array fieldTypes = {
        typeMgr.typeU32(),
        typeMgr.typeU32(),
    };
    const TypeRef structTypeRef = makeStructType(ctx, fieldTypes);

    constexpr uint32_t        a = 11;
    constexpr uint32_t        b = 31;
    const SmallVector<FFIArgument> args = {
        {.typeRef = typeMgr.typeU32(), .valuePtr = &a},
        {.typeRef = typeMgr.typeU32(), .valuePtr = &b},
    };

    FFIStructPair32 result = {};
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeReturnStructPair32), args, structTypeRef, &result));
    if (result.a != a || result.b != b)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeStructReturnByReference)
{
    if (CallConv::host().classifyStructReturnPassing(sizeof(FFIStructTriple64)) != StructArgPassingKind::ByReference)
        return Result::Continue;

    const auto& typeMgr = ctx.typeMgr();

    const std::array fieldTypes = {
        typeMgr.typeU64(),
        typeMgr.typeU64(),
        typeMgr.typeU64(),
    };
    const TypeRef structTypeRef = makeStructType(ctx, fieldTypes);

    constexpr uint64_t       seed = 39;
    const SmallVector<FFIArgument> args = {
        {.typeRef = typeMgr.typeU64(), .valuePtr = &seed},
    };

    FFIStructTriple64 result = {};
    RESULT_VERIFY(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeReturnStructTriple64), args, structTypeRef, &result));
    if (result.a != 40 || result.b != 41 || result.c != 42)
        return Result::Error;
}
SWC_TEST_END()

#endif
#endif

SWC_END_NAMESPACE();
