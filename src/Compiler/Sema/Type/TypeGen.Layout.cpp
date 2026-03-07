#include "pch.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE();

TypeGen::LayoutKind TypeGen::layoutKindOf(const TypeInfo& type)
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

Result TypeGen::rtTypeRefFor(Sema& sema, LayoutKind kind, TypeRef& typeRef, const SourceCodeRef& codeRef)
{
    using Pn = IdentifierManager::PredefinedName;

    SWC_RESULT_VERIFY(sema.waitPredefined(Pn::TypeInfo, typeRef, codeRef));
    SWC_RESULT_VERIFY(sema.waitPredefined(Pn::TypeValue, typeRef, codeRef));

    auto predefinedName = Pn::TypeInfo;
    switch (kind)
    {
        case LayoutKind::Native: predefinedName = Pn::TypeInfoNative; break;
        case LayoutKind::Enum: predefinedName = Pn::TypeInfoEnum; break;
        case LayoutKind::Array: predefinedName = Pn::TypeInfoArray; break;
        case LayoutKind::Slice: predefinedName = Pn::TypeInfoSlice; break;
        case LayoutKind::Pointer: predefinedName = Pn::TypeInfoPointer; break;
        case LayoutKind::Struct: predefinedName = Pn::TypeInfoStruct; break;
        case LayoutKind::Alias: predefinedName = Pn::TypeInfoAlias; break;
        case LayoutKind::Variadic: predefinedName = Pn::TypeInfoVariadic; break;
        case LayoutKind::TypedVariadic: predefinedName = Pn::TypeInfoVariadic; break;
        case LayoutKind::Func: predefinedName = Pn::TypeInfoFunc; break;
        case LayoutKind::Base: predefinedName = Pn::TypeInfo; break;
    }

    SWC_RESULT_VERIFY(sema.waitPredefined(predefinedName, typeRef, codeRef));
    if (typeRef.isInvalid())
        return Result::Pause;
    return Result::Continue;
}

SWC_END_NAMESPACE();
