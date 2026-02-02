#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Type/TypeGen.Internal.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace TypeGenInternal
{
    LayoutKind layoutKindOf(const TypeInfo& type)
    {
        if (type.isBool() || type.isInt() || type.isFloat() || type.isChar() || type.isString() || type.isCString() ||
            type.isRune() || type.isAny() || type.isVoid() || type.isUndefined())
            return LayoutKind::Native;

        if (type.isEnum())
            return LayoutKind::Enum;
        if (type.isArray())
            return LayoutKind::Array;
        if (type.isSlice())
            return LayoutKind::Slice;
        if (type.isAlias())
            return LayoutKind::Alias;
        if (type.isAnyVariadic())
            return type.isTypedVariadic() ? LayoutKind::TypedVariadic : LayoutKind::Variadic;
        if (type.isFunction())
            return LayoutKind::Func;
        if (type.isPointerLike())
            return LayoutKind::Pointer;
        if (type.isStruct())
            return LayoutKind::Struct;

        return LayoutKind::Base;
    }

    TypeRef rtTypeRefFor(const TypeManager& tm, LayoutKind kind)
    {
        switch (kind)
        {
            case LayoutKind::Native: return tm.structTypeInfoNative();
            case LayoutKind::Enum: return tm.structTypeInfoEnum();
            case LayoutKind::Array: return tm.structTypeInfoArray();
            case LayoutKind::Slice: return tm.structTypeInfoSlice();
            case LayoutKind::Pointer: return tm.structTypeInfoPointer();
            case LayoutKind::Struct: return tm.structTypeInfoStruct();
            case LayoutKind::Alias: return tm.structTypeInfoAlias();
            case LayoutKind::Variadic: return tm.structTypeInfoVariadic();
            case LayoutKind::TypedVariadic: return tm.structTypeInfoVariadic();
            case LayoutKind::Func: return tm.structTypeInfoFunc();
            case LayoutKind::Base: return tm.structTypeInfo();
        }

        return tm.structTypeInfo();
    }

    Result ensureTypeInfoStructReady(Sema& sema, const TypeManager& tm, TypeRef rtTypeRef, const AstNode& node)
    {
        if (rtTypeRef.isInvalid())
            return sema.waitIdentifier(sema.idMgr().predefined(IdentifierManager::PredefinedName::TypeInfo), node.codeRef());

        const auto& structType = tm.get(rtTypeRef);
        if (!structType.isCompleted(sema.ctx()))
            return sema.waitCompleted(&structType.payloadSymStruct(), node.codeRef());

        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
