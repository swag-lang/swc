#include "pch.h"
#include "Compiler/Sema/Type/IntrinsicInitType.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool preservesAliasType(const TypeInfo& rawType)
    {
        return rawType.isEnum() ||
               rawType.isBool() ||
               rawType.isIntLike() ||
               rawType.isFloat() ||
               rawType.isAnyPointer() ||
               rawType.isReference() ||
               rawType.isCString() ||
               rawType.isTypeInfo() ||
               (rawType.isFunction() && !rawType.isLambdaClosure());
    }
}

TypeRef IntrinsicInitType::normalizeTypeRef(TaskContext& ctx, TypeRef typeRef)
{
    if (!typeRef.isValid())
        return TypeRef::invalid();

    const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
    if (!typeInfo.isAlias())
        return typeRef;

    const TypeRef rawTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
    if (rawTypeRef.isValid() && !preservesAliasType(ctx.typeMgr().get(rawTypeRef)))
        return rawTypeRef;

    return typeRef;
}

SWC_END_NAMESPACE();
