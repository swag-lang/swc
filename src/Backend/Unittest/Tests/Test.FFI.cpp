#include "pch.h"
#include "Backend/FFI/FFI.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Core/SmallVector.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST
#ifdef _M_X64

namespace
{
    Result callCaseTyped(TaskContext& ctx, void* targetFn, std::span<const FFIArgument> args, TypeRef retTypeRef, void* outRetValue)
    {
        FFI::callFFI(ctx, targetFn, args, {.typeRef = retTypeRef, .valuePtr = outRetValue});
        return Result::Continue;
    }
}

namespace
{
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
}

SWC_TEST_BEGIN(FFI_CallNativeNoArgBool)
{
    const auto& typeMgr = ctx.typeMgr();
    bool  result  = false;
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

#endif
#endif

SWC_END_NAMESPACE();
