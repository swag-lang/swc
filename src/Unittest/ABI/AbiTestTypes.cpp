#include "pch.h"

#if SWC_HAS_UNITTEST
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"
#include "Unittest/ABI/AbiTestTypes.h"

SWC_BEGIN_NAMESPACE();

TypeRef Backend::Unittest::makeStructType(TaskContext& ctx, const std::span<const TypeRef> fieldTypes, const bool isUnion, const TypeRef tagType)
{
    auto* record = Symbol::make<SymbolStruct>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    if (isUnion)
        record->addExtraFlag(SymbolStructFlagsE::Union);
    if (tagType.isValid())
    {
        record->addExtraFlag(SymbolStructFlagsE::Tagged);
        record->setTaggedTypeRef(tagType);
    }
    for (const TypeRef fieldType : fieldTypes)
    {
        auto* field = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        field->setTypeRef(fieldType);
        record->addField(field);
    }
    SWC_ASSERT(record->computeLayout(ctx) == Result::Continue);
    const TypeRef type = ctx.typeMgr().addType(TypeInfo::makeStruct(record));
    record->setTypeRef(type);
    return type;
}

SWC_END_NAMESPACE();
#endif
