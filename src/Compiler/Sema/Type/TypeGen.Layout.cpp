#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Type/TypeGen.Internal.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    IdentifierRef typeInfoIdentifierFor(TypeGenInternal::LayoutKind kind, const IdentifierManager& idMgr)
    {
        using Pn = IdentifierManager::PredefinedName;
        switch (kind)
        {
            case TypeGenInternal::LayoutKind::Native: return idMgr.predefined(Pn::TypeInfoNative);
            case TypeGenInternal::LayoutKind::Enum: return idMgr.predefined(Pn::TypeInfoEnum);
            case TypeGenInternal::LayoutKind::Array: return idMgr.predefined(Pn::TypeInfoArray);
            case TypeGenInternal::LayoutKind::Slice: return idMgr.predefined(Pn::TypeInfoSlice);
            case TypeGenInternal::LayoutKind::Pointer: return idMgr.predefined(Pn::TypeInfoPointer);
            case TypeGenInternal::LayoutKind::Struct: return idMgr.predefined(Pn::TypeInfoStruct);
            case TypeGenInternal::LayoutKind::Alias: return idMgr.predefined(Pn::TypeInfoAlias);
            case TypeGenInternal::LayoutKind::Variadic: return idMgr.predefined(Pn::TypeInfoVariadic);
            case TypeGenInternal::LayoutKind::TypedVariadic: return idMgr.predefined(Pn::TypeInfoVariadic);
            case TypeGenInternal::LayoutKind::Func: return idMgr.predefined(Pn::TypeInfoFunc);
            case TypeGenInternal::LayoutKind::Base: return idMgr.predefined(Pn::TypeInfo);
        }

        return idMgr.predefined(Pn::TypeInfo);
    }
}

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

    Result ensureTypeInfoStructReady(Sema& sema, const TypeManager& tm, LayoutKind kind, TypeRef rtTypeRef, const AstNode& node)
    {
        if (rtTypeRef.isInvalid())
        {
            MatchContext lookUpCxt;
            lookUpCxt.codeRef         = node.codeRef();
            const IdentifierRef idRef = typeInfoIdentifierFor(kind, sema.idMgr());
            RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));
            for (const Symbol* sym : lookUpCxt.symbols())
                RESULT_VERIFY(sema.waitSemaCompleted(sym, node.codeRef()));
            return Result::Pause;
        }

        const auto& structType = tm.get(rtTypeRef);
        RESULT_VERIFY(sema.waitSemaCompleted(&structType.payloadSymStruct(), node.codeRef()));

        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
