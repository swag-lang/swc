#include "pch.h"
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

    uint32_t   offset   = 0;
    const Utf8 name     = type.toName(ctx);
    const Utf8 fullname = name;

    Runtime::TypeInfo* rtTypePtr = nullptr;
    if (type.isBool() || type.isInt() || type.isFloat() || type.isString() || type.isRune() || type.isAny() || type.isVoid())
    {
        Runtime::TypeInfoNative* rtNative;
        offset    = storage.reserve(&rtNative);
        rtTypePtr = &rtNative->base;
        rtNative->base.kind  = Runtime::TypeInfoKind::Native;
        rtNative->nativeKind = Runtime::TypeInfoNativeKind::Void;

        if (type.isBool())
            rtNative->nativeKind = Runtime::TypeInfoNativeKind::Bool;
        else if (type.isInt())
        {
            rtNative->base.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtNative->base.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Integer));
            if (type.isIntUnsigned())
                rtNative->base.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtNative->base.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Unsigned));

            switch (type.intBits())
            {
                case 8:
                    rtNative->nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U8 : Runtime::TypeInfoNativeKind::S8;
                    break;
                case 16:
                    rtNative->nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U16 : Runtime::TypeInfoNativeKind::S16;
                    break;
                case 32:
                    rtNative->nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U32 : Runtime::TypeInfoNativeKind::S32;
                    break;
                case 64:
                    rtNative->nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U64 : Runtime::TypeInfoNativeKind::S64;
                    break;
            }
        }
        else if (type.isFloat())
        {
            rtNative->base.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtNative->base.flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Float));
            rtNative->nativeKind = type.floatBits() == 32 ? Runtime::TypeInfoNativeKind::F32 : Runtime::TypeInfoNativeKind::F64;
        }
        else if (type.isString())
            rtNative->nativeKind = Runtime::TypeInfoNativeKind::String;
        else if (type.isRune())
            rtNative->nativeKind = Runtime::TypeInfoNativeKind::Rune;
        else if (type.isAny())
            rtNative->nativeKind = Runtime::TypeInfoNativeKind::Any;
        else if (type.isVoid())
            rtNative->nativeKind = Runtime::TypeInfoNativeKind::Void;
    }
    else if (type.isEnum())
    {
        Runtime::TypeInfoEnum* rtEnum;
        offset    = storage.reserve(&rtEnum);
        rtTypePtr = &rtEnum->base;
        rtEnum->base.kind = Runtime::TypeInfoKind::Enum;
    }
    else if (type.isArray())
    {
        Runtime::TypeInfoArray* rtArray;
        offset    = storage.reserve(&rtArray);
        rtTypePtr = &rtArray->base;
        rtArray->base.kind  = Runtime::TypeInfoKind::Array;
        rtArray->count      = type.arrayDims().empty() ? 0 : type.arrayDims()[0];
        rtArray->totalCount = type.arrayDims().empty() ? 0 : type.arrayDims()[0];
        for (size_t i = 1; i < type.arrayDims().size(); i++)
            rtArray->totalCount *= type.arrayDims()[i];
    }
    else if (type.isSlice())
    {
        Runtime::TypeInfoSlice* rtSlice;
        offset    = storage.reserve(&rtSlice);
        rtTypePtr = &rtSlice->base;
        rtSlice->base.kind = Runtime::TypeInfoKind::Slice;
    }
    else if (type.isPointerLike())
    {
        Runtime::TypeInfoPointer* rtPtr;
        offset    = storage.reserve(&rtPtr);
        rtTypePtr = &rtPtr->base;
        rtPtr->base.kind = Runtime::TypeInfoKind::Pointer;
    }
    else if (type.isStruct())
    {
        Runtime::TypeInfoStruct* rtStruct;
        offset    = storage.reserve(&rtStruct);
        rtTypePtr = &rtStruct->base;
        rtStruct->base.kind = Runtime::TypeInfoKind::Struct;
    }
    else
    {
        offset = storage.reserve(&rtTypePtr);
    }

    rtTypePtr->sizeofType = static_cast<uint32_t>(type.sizeOf(ctx));
    rtTypePtr->crc        = type.hash();
    rtTypePtr->flags      = Runtime::TypeInfoFlags::Zero;
    if (type.isConst())
        rtTypePtr->flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtTypePtr->flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Const));
    if (type.isNullable())
        rtTypePtr->flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rtTypePtr->flags) | static_cast<uint32_t>(Runtime::TypeInfoFlags::Nullable));

    result.view = std::string_view{storage.ptr<char>(offset), structType.sizeOf(ctx)};

    rtTypePtr->fullname.length = storage.addString(offset, offsetof(Runtime::TypeInfo, fullname.ptr), fullname);
    rtTypePtr->name.length     = storage.addString(offset, offsetof(Runtime::TypeInfo, name.ptr), name);

    if (type.isStruct())
    {
        const auto rtStructPtr         = storage.ptr<Runtime::TypeInfoStruct>(offset);
        rtStructPtr->structName.length = storage.addString(offset, offsetof(Runtime::TypeInfoStruct, structName.ptr), name);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
