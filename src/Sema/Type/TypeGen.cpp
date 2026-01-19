#include "pch.h"
#include <cstddef>
#include "Sema/Type/TypeGen.h"
#include "Core/DataSegment.h"
#include "Main/TaskContext.h"
#include "Runtime/Runtime.h"
#include "Sema/Core/Sema.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

Result TypeGen::makeTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenResult& result)
{
    auto&          ctx     = sema.ctx();
    const auto&    typeMgr = ctx.typeMgr();
    const auto&    type    = typeMgr.get(typeRef);
    const AstNode& node    = sema.node(ownerNodeRef);

    TypeRef structTypeRef;
    if (type.isBool() || type.isInt() || type.isFloat() || type.isString() || type.isRune() || type.isAny() || type.isVoid())
        structTypeRef = typeMgr.structTypeInfoNative();
    else if (type.isEnum())
        structTypeRef = typeMgr.structTypeInfoEnum();
    else if (type.isArray())
        structTypeRef = typeMgr.structTypeInfoArray();
    else if (type.isSlice())
        structTypeRef = typeMgr.structTypeInfoSlice();
    else if (type.isPointerLike())
        structTypeRef = typeMgr.structTypeInfoPointer();
    else if (type.isStruct())
        structTypeRef = typeMgr.structTypeInfoStruct();
    else
        structTypeRef = typeMgr.structTypeInfo();

    if (structTypeRef.isInvalid())
        return sema.waitIdentifier(sema.idMgr().nameTypeInfo(), node.srcViewRef(), node.tokRef());
    const auto& structType = typeMgr.get(structTypeRef);
    if (!structType.isCompleted(ctx))
        return sema.waitCompleted(&structType.symStruct(), node.srcViewRef(), node.tokRef());

    result.structTypeRef = structTypeRef;

    uint32_t          offset = 0;
    Runtime::TypeInfo rtType;
    const Utf8        name           = type.toName(ctx);
    const Utf8        fullname       = name;
    const auto        cstFullnameStr = storage.addString(fullname);
    const auto        cstNameStr     = storage.addString(name);
    rtType.fullname.ptr              = const_cast<char*>(cstFullnameStr.data());
    rtType.fullname.length           = cstFullnameStr.size();
    rtType.name.ptr                  = const_cast<char*>(cstNameStr.data());
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
        offset              = storage.add(rtNative);
    }
    else if (type.isInt())
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

        offset = storage.add(rtNative);
    }
    else if (type.isFloat())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.base.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtNative.base.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Float));
        rtNative.nativeKind = type.floatBits() == 32 ? Runtime::TypeInfoNativeKind::F32 : Runtime::TypeInfoNativeKind::F64;
        offset              = storage.add(rtNative);
    }
    else if (type.isString())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::String;
        offset              = storage.add(rtNative);
    }
    else if (type.isRune())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::Rune;
        offset              = storage.add(rtNative);
    }
    else if (type.isAny())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::Any;
        offset              = storage.add(rtNative);
    }
    else if (type.isVoid())
    {
        Runtime::TypeInfoNative rtNative;
        rtNative.base       = rtType;
        rtNative.base.kind  = Runtime::TypeInfoKind::Native;
        rtNative.nativeKind = Runtime::TypeInfoNativeKind::Void;
        offset              = storage.add(rtNative);
    }
    else if (type.isEnum())
    {
        Runtime::TypeInfoEnum rtEnum;
        rtEnum.base       = rtType;
        rtEnum.base.kind  = Runtime::TypeInfoKind::Enum;
        rtEnum.rawType    = nullptr;
        rtEnum.values     = {nullptr, 0};
        rtEnum.attributes = {nullptr, 0};
        offset            = storage.add(rtEnum);
    }
    else if (type.isArray())
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
        offset              = storage.add(rtArray);
    }
    else if (type.isSlice())
    {
        Runtime::TypeInfoSlice rtSlice;
        rtSlice.base        = rtType;
        rtSlice.base.kind   = Runtime::TypeInfoKind::Slice;
        rtSlice.pointedType = nullptr;
        offset              = storage.add(rtSlice);
    }
    else if (type.isPointerLike())
    {
        Runtime::TypeInfoPointer rtPtr;
        rtPtr.base        = rtType;
        rtPtr.base.kind   = Runtime::TypeInfoKind::Pointer;
        rtPtr.pointedType = nullptr;
        offset            = storage.add(rtPtr);
    }
    else if (type.isStruct())
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
        offset               = storage.add(rtStruct);
    }
    else
    {
        // Default to base TypeInfo if specialized one not found/implemented
        offset = storage.add(rtType);
    }

    result.view = std::string_view{storage.ptr<char>(offset), structType.sizeOf(ctx)};

    if (rtType.fullname.ptr)
        storage.addRelocation(offset + offsetof(Runtime::TypeInfo, fullname.ptr), storage.offset(rtType.fullname.ptr));
    if (rtType.name.ptr)
        storage.addRelocation(offset + offsetof(Runtime::TypeInfo, name.ptr), storage.offset(rtType.name.ptr));

    if (type.isStruct())
    {
        if (rtType.name.ptr)
            storage.addRelocation(offset + offsetof(Runtime::TypeInfoStruct, structName.ptr), storage.offset(rtType.name.ptr));
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
