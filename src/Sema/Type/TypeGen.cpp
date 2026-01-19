#include "pch.h"
#include "Sema/Type/TypeGen.h"
#include "Core/DataSegment.h"
#include "Main/TaskContext.h"
#include "Runtime/Runtime.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

uint32_t TypeGen::makeConstantTypeInfo(TaskContext& ctx, DataSegment& storage, TypeRef typeRef)
{
    const auto& typeMgr = ctx.typeMgr();
    const auto& type    = typeMgr.get(typeRef);

    Runtime::TypeInfo rtType;
    const Utf8        name           = type.toName(ctx);
    const Utf8        fullname       = name;
    const auto        cstFullnameStr = storage.addString(fullname);
    const auto        cstNameStr     = storage.addString(name);
    rtType.fullname.ptr              = cstFullnameStr.data();
    rtType.fullname.length           = cstFullnameStr.size();
    rtType.name.ptr                  = cstNameStr.data();
    rtType.name.length               = cstNameStr.size();
    rtType.sizeofType                = static_cast<uint32_t>(type.sizeOf(ctx));
    rtType.crc                       = type.hash();
    rtType.flags                     = Runtime::TypeInfoFlags::Zero;
    if (type.isConst())
        rtType.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtType.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Const));
    if (type.isNullable())
        rtType.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtType.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Nullable));

    if (type.isBool())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::Bool;
        return storage.add(rtNative);
    }

    if (type.isInt())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.base.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtNative.base.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Integer));
        if (type.isIntUnsigned())
            rtNative.base.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtNative.base.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Unsigned));

        switch (type.intBits())
        {
            case 8:
                rtNative.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U8 : Runtime::TypeInfoNativeKind::S8;
                break;
            case 16:
                rtNative.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U16 : Runtime::TypeInfoNativeKind::S16;
                break;
            case 32:
                rtNative.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U32 : Runtime::TypeInfoNativeKind::S32;
                break;
            case 64:
                rtNative.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U64 : Runtime::TypeInfoNativeKind::S64;
                break;
            default:
                rtNative.nativeKind = Runtime::TypeInfoNativeKind::Void;
                break;
        }

        return storage.add(rtNative);
    }

    if (type.isFloat())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.base.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtNative.base.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Float));
        rtNative.nativeKind = type.floatBits() == 32 ? Runtime::TypeInfoNativeKind::F32 : Runtime::TypeInfoNativeKind::F64;
        return storage.add(rtNative);
    }

    if (type.isString())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::String;
        return storage.add(rtNative);
    }

    if (type.isRune())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::Rune;
        return storage.add(rtNative);
    }

    if (type.isAny())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::Any;
        return storage.add(rtNative);
    }

    if (type.isVoid())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::Void;
        return storage.add(rtNative);
    }

    if (type.isEnum())
    {
        Runtime::TypeInfoEnum rtEnum;
        rtEnum.base       = rtType;
        rtEnum.base.kind  = Runtime::TypeInfoKind::Enum;
        rtEnum.rawType    = nullptr;
        rtEnum.values     = {nullptr, 0};
        rtEnum.attributes = {nullptr, 0};
        return storage.add(rtEnum);
    }

    if (type.isArray())
    {
        Runtime::TypeInfoArray rtArray;
        rtArray.base       = rtType;
        rtArray.base.kind  = Runtime::TypeInfoKind::Array;
        rtArray.count      = type.arrayDims().empty() ? 0 : type.arrayDims()[0];
        rtArray.totalCount = type.arrayDims().empty() ? 0 : type.arrayDims()[0];
        for (size_t i = 1; i < type.arrayDims().size(); i++)
            rtArray.totalCount *= type.arrayDims()[i];
        rtArray.pointedType = nullptr;
        rtArray.finalType   = nullptr;
        return storage.add(rtArray);
    }

    if (type.isSlice())
    {
        Runtime::TypeInfoSlice rtSlice;
        rtSlice.base        = rtType;
        rtSlice.base.kind   = Runtime::TypeInfoKind::Slice;
        rtSlice.pointedType = nullptr;
        return storage.add(rtSlice);
    }

    if (type.isPointerLike())
    {
        Runtime::TypeInfoPointer rtPtr;
        rtPtr.base        = rtType;
        rtPtr.base.kind   = Runtime::TypeInfoKind::Pointer;
        rtPtr.pointedType = nullptr;
        return storage.add(rtPtr);
    }

    if (type.isStruct())
    {
        Runtime::TypeInfoStruct rtStruct;
        rtStruct.base        = rtType;
        rtStruct.base.kind   = Runtime::TypeInfoKind::Struct;
        rtStruct.opInit      = nullptr;
        rtStruct.opDrop      = nullptr;
        rtStruct.opPostCopy  = nullptr;
        rtStruct.opPostMove  = nullptr;
        rtStruct.structName  = rtType.name;
        rtStruct.fields      = {nullptr, 0};
        rtStruct.usingFields = {nullptr, 0};
        rtStruct.methods     = {nullptr, 0};
        rtStruct.interfaces  = {nullptr, 0};
        rtStruct.generics    = {nullptr, 0};
        rtStruct.attributes  = {nullptr, 0};
        rtStruct.fromGeneric = nullptr;
        return storage.add(rtStruct);
    }

    // Default to base TypeInfo if specialized one not found/implemented
    return storage.add(rtType);
}

SWC_END_NAMESPACE();
