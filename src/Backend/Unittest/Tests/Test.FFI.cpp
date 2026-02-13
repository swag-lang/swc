#include "pch.h"
#include "Backend/FFI/FFI.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST
#ifdef _M_X64

namespace
{
    Result callCase(TaskContext& ctx, void* targetFn, std::span<const Backend::FFIArgumentDesc> args, Backend::FFITypeDesc retTypeDesc, void* outRetValue)
    {
        return Backend::FFI::callFFI(ctx, targetFn, args, {.typeDesc = retTypeDesc, .valuePtr = outRetValue});
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
    bool result = false;
    RESULT_VERIFY(callCase(ctx, reinterpret_cast<void*>(&ffiNativeReturnTrue), std::span<const Backend::FFIArgumentDesc>{}, {.valueClass = Backend::FFIValueClass::Int, .numBits = 8}, &result));
    if (!result)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeU8)
{
    const uint8_t a = 19;
    const uint8_t b = 23;
    const std::vector<Backend::FFIArgumentDesc> args = {
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 8}, .valuePtr = &a},
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 8}, .valuePtr = &b},
    };

    uint8_t result = 0;
    RESULT_VERIFY(callCase(ctx, reinterpret_cast<void*>(&ffiNativeAddU8), args, {.valueClass = Backend::FFIValueClass::Int, .numBits = 8}, &result));
    if (result != 42)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeI32)
{
    const int32_t a = -1200;
    const int32_t b = -137;
    const std::vector<Backend::FFIArgumentDesc> args = {
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 32}, .valuePtr = &a},
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 32}, .valuePtr = &b},
    };

    int32_t result = 0;
    RESULT_VERIFY(callCase(ctx, reinterpret_cast<void*>(&ffiNativeAddI32), args, {.valueClass = Backend::FFIValueClass::Int, .numBits = 32}, &result));
    if (result != -1337)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeF32)
{
    const float a = 0.5f;
    const float b = 1.25f;
    const std::vector<Backend::FFIArgumentDesc> args = {
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Float, .numBits = 32}, .valuePtr = &a},
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Float, .numBits = 32}, .valuePtr = &b},
    };

    float result = 0;
    RESULT_VERIFY(callCase(ctx, reinterpret_cast<void*>(&ffiNativeAddF32), args, {.valueClass = Backend::FFIValueClass::Float, .numBits = 32}, &result));
    if (result != 1.75f)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeF64)
{
    const double a = 1.5;
    const double b = 2.5;
    const std::vector<Backend::FFIArgumentDesc> args = {
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Float, .numBits = 64}, .valuePtr = &a},
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Float, .numBits = 64}, .valuePtr = &b},
    };

    double result = 0;
    RESULT_VERIFY(callCase(ctx, reinterpret_cast<void*>(&ffiNativeAddF64), args, {.valueClass = Backend::FFIValueClass::Float, .numBits = 64}, &result));
    if (result != 4.0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeMixedArgs)
{
    const uint8_t  a = 1;
    const uint16_t b = 2;
    const uint32_t c = 70000;
    const uint64_t d = 0;
    const std::vector<Backend::FFIArgumentDesc> args = {
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 8}, .valuePtr = &a},
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 16}, .valuePtr = &b},
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 32}, .valuePtr = &c},
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 64}, .valuePtr = &d},
    };

    uint64_t result = 0;
    RESULT_VERIFY(callCase(ctx, reinterpret_cast<void*>(&ffiNativeMixArgs), args, {.valueClass = Backend::FFIValueClass::Int, .numBits = 64}, &result));
    if (result != 70003ULL)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeStackArgs)
{
    const int64_t a = 1;
    const int64_t b = 2;
    const int64_t c = 3;
    const int64_t d = 4;
    const int64_t e = 5;
    const int64_t f = 6;
    const std::vector<Backend::FFIArgumentDesc> args = {
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 64}, .valuePtr = &a},
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 64}, .valuePtr = &b},
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 64}, .valuePtr = &c},
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 64}, .valuePtr = &d},
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 64}, .valuePtr = &e},
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 64}, .valuePtr = &f},
    };

    int64_t result = 0;
    RESULT_VERIFY(callCase(ctx, reinterpret_cast<void*>(&ffiNativeStackArgs), args, {.valueClass = Backend::FFIValueClass::Int, .numBits = 64}, &result));
    if (result != 21)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativePointerArg)
{
    const void* ptr = reinterpret_cast<void*>(0x10);
    const std::vector<Backend::FFIArgumentDesc> args = {
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 64}, .valuePtr = &ptr},
    };

    bool result = false;
    RESULT_VERIFY(callCase(ctx, reinterpret_cast<void*>(&ffiNativeConsumePtr), args, {.valueClass = Backend::FFIValueClass::Int, .numBits = 8}, &result));
    if (!result)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeErrorInvalidArgTypeDesc)
{
    const uint64_t value = 42;
    const std::vector<Backend::FFIArgumentDesc> args = {
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 24}, .valuePtr = &value},
    };

    uint64_t result = 0;
    if (Backend::FFI::callFFI(ctx, reinterpret_cast<void*>(&ffiNativeMixArgs), args, {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 64}, .valuePtr = &result}) != Result::Error)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeErrorNullArgValue)
{
    const std::vector<Backend::FFIArgumentDesc> args = {
        {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 8}, .valuePtr = nullptr},
    };

    uint8_t result = 0;
    if (Backend::FFI::callFFI(ctx, reinterpret_cast<void*>(&ffiNativeAddU8), args, {.typeDesc = {.valueClass = Backend::FFIValueClass::Int, .numBits = 8}, .valuePtr = &result}) != Result::Error)
        return Result::Error;
}
SWC_TEST_END()

#endif
#endif

SWC_END_NAMESPACE();
