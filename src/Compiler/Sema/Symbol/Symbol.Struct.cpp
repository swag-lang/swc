#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool compareFunctionOrder(const SymbolFunction* left, const SymbolFunction* right)
    {
        SWC_ASSERT(left);
        SWC_ASSERT(right);
        return left->tokRef().get() < right->tokRef().get();
    }

    bool isRuntimeReflectedMethod(const SymbolFunction& symFunc)
    {
        if (symFunc.isIgnored() || symFunc.isAttribute() || symFunc.isEmpty())
            return false;
        if (symFunc.attributes().hasRtFlag(RtAttributeFlagsE::Implicit))
            return false;

        const SymbolStruct* ownerStruct = symFunc.ownerStruct();
        if (ownerStruct && ownerStruct->isGenericRoot() && !ownerStruct->isGenericInstance())
            return false;

        if (symFunc.isGenericRoot() && !symFunc.isGenericInstance())
            return false;

        if (!symFunc.returnTypeRef().isValid())
            return false;

        for (const SymbolVariable* param : symFunc.parameters())
        {
            if (!param || !param->typeRef().isValid())
                return false;
        }

        return true;
    }

    const SymbolFunction* registeredLifecycleFunction(const SymbolStruct& ownerStruct, const SpecOpKind kind)
    {
        switch (kind)
        {
            case SpecOpKind::OpDrop:
                return ownerStruct.opDrop();
            case SpecOpKind::OpPostCopy:
                return ownerStruct.opPostCopy();
            case SpecOpKind::OpPostMove:
                return ownerStruct.opPostMove();
            default:
                return nullptr;
        }
    }

    const SymbolFunction* resolvedLifecycleFunction(TaskContext& ctx, const SymbolStruct& ownerStruct, const SpecOpKind kind)
    {
        if (const SymbolFunction* symFunc = registeredLifecycleFunction(ownerStruct, kind); symFunc && symFunc->isSemaCompleted())
            return symFunc;

        for (const SymbolFunction* symFunc : ownerStruct.declaredMethods())
        {
            if (!symFunc || symFunc->attributes().hasRtFlag(RtAttributeFlagsE::Implicit))
                continue;
            if (const SymbolImpl* symImpl = symFunc->declImplContext(); symImpl && symImpl->isForInterface())
                continue;
            if (!symFunc->isDeclared() || !symFunc->isTyped() || !symFunc->isSemaCompleted())
                continue;
            if (symFunc->specOpKind() == kind)
                return symFunc;
        }

        SWC_UNUSED(ctx);
        return registeredLifecycleFunction(ownerStruct, kind);
    }

    const SymbolFunction* findGeneratedImplicitMethod(TaskContext& ctx, const SymbolStruct& ownerStruct, const std::string_view expectedName)
    {
        if (expectedName.empty())
            return nullptr;

        for (const SymbolFunction* symFunc : ownerStruct.declaredMethods())
        {
            if (!symFunc)
                continue;
            if (!symFunc->attributes().hasRtFlag(RtAttributeFlagsE::Implicit))
                continue;
            if (!symFunc->isDeclared() || !symFunc->isTyped() || !symFunc->isSemaCompleted())
                continue;
            if (symFunc->name(ctx) == expectedName)
                return symFunc;
        }

        return nullptr;
    }

    const SymbolFunction* findGeneratedLifecycleWrapper(TaskContext& ctx, const SymbolStruct& ownerStruct, const SpecOpKind kind)
    {
        return findGeneratedImplicitMethod(ctx, ownerStruct, SemaSpecOp::generatedLifecycleWrapperName(kind));
    }

    const SymbolFunction* findGeneratedInitWrapper(TaskContext& ctx, const SymbolStruct& ownerStruct)
    {
        return findGeneratedImplicitMethod(ctx, ownerStruct, SemaSpecOp::generatedInitWrapperName());
    }

    Result lowerImplicitDefaultBytes(Sema& sema, ByteSpanRW dstBytes, TypeRef typeRef)
    {
        const TypeInfo& rawType = sema.typeMgr().get(typeRef);
        if (const TypeRef storageTypeRef = rawType.unwrap(sema.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum); storageTypeRef.isValid())
            typeRef = storageTypeRef;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isStruct())
        {
            for (const SymbolVariable* field : type.payloadSymStruct().fields())
            {
                if (!field)
                    continue;

                const TypeRef   fieldTypeRef = field->typeRef();
                const TypeInfo& fieldType    = sema.typeMgr().get(fieldTypeRef);
                const uint64_t  fieldSize    = fieldType.sizeOf(sema.ctx());
                const uint64_t  fieldOffset  = field->offset();
                SWC_ASSERT(fieldOffset + fieldSize <= dstBytes.size());

                ByteSpanRW fieldBytes = dstBytes.subspan(static_cast<size_t>(fieldOffset), static_cast<size_t>(fieldSize));
                if (const ConstantRef valueRef = field->defaultValueRef(); valueRef.isValid())
                {
                    SWC_RESULT(ConstantLower::lowerToBytes(sema, fieldBytes, valueRef, fieldTypeRef));
                }
                else if (fieldSize)
                {
                    SWC_RESULT(lowerImplicitDefaultBytes(sema, fieldBytes, fieldTypeRef));
                }
            }

            return Result::Continue;
        }

        if (type.isArray())
        {
            const TypeRef   elemTypeRef = type.payloadArrayElemTypeRef();
            const TypeInfo& elemType    = sema.typeMgr().get(elemTypeRef);
            const uint64_t  elemSize    = elemType.sizeOf(sema.ctx());
            if (!elemSize)
                return Result::Continue;

            uint64_t totalCount = 1;
            for (const uint64_t dim : type.payloadArrayDims())
                totalCount *= dim;

            for (uint64_t idx = 0; idx < totalCount; ++idx)
                SWC_RESULT(lowerImplicitDefaultBytes(sema, dstBytes.subspan(static_cast<size_t>(idx * elemSize), static_cast<size_t>(elemSize)), elemTypeRef));
            return Result::Continue;
        }

        if (!dstBytes.empty())
            std::memset(dstBytes.data(), 0, dstBytes.size());
        return Result::Continue;
    }

    void appendImplFunctions(std::vector<SymbolFunction*>& out, const std::vector<SymbolImpl*>& implList)
    {
        for (const SymbolImpl* symImpl : implList)
        {
            if (!symImpl)
                continue;

            std::vector<const Symbol*> symbols;
            symImpl->getAllSymbols(symbols);
            for (const Symbol* symbol : symbols)
            {
                if (!symbol || !symbol->isFunction())
                    continue;

                out.push_back(const_cast<SymbolFunction*>(&symbol->cast<SymbolFunction>()));
            }
        }
    }

    bool sameAttributeInstance(const AttributeInstance& lhs, const AttributeInstance& rhs)
    {
        if (lhs.symbol != rhs.symbol || lhs.params.size() != rhs.params.size())
            return false;

        for (size_t i = 0; i < lhs.params.size(); ++i)
        {
            const auto& lhsParam = lhs.params[i];
            const auto& rhsParam = rhs.params[i];
            if (lhsParam.nameIdRef != rhsParam.nameIdRef || lhsParam.valueCstRef != rhsParam.valueCstRef)
                return false;
        }

        return true;
    }

    size_t inheritedAttributePrefixCount(const AttributeList& attributes, const AttributeList& inheritedAttributes)
    {
        const size_t inheritedCount = std::min(attributes.attributes.size(), inheritedAttributes.attributes.size());
        size_t       prefixCount    = 0;
        while (prefixCount < inheritedCount && sameAttributeInstance(attributes.attributes[prefixCount], inheritedAttributes.attributes[prefixCount]))
            prefixCount++;

        return prefixCount;
    }

    bool tryGetSwagLayoutAttributeValue(uint32_t& outValue, TaskContext& ctx, const AttributeList& attributes, const std::string_view attrName)
    {
        outValue = 0;
        for (const AttributeInstance& attribute : attributes.attributes)
        {
            if (!attribute.symbol || !attribute.symbol->inSwagNamespace(ctx) || attribute.symbol->name(ctx) != attrName)
                continue;

            for (const AttributeParamInstance& param : attribute.params)
            {
                if (!param.valueCstRef.isValid())
                    continue;

                const ConstantValue& cst = ctx.cstMgr().get(param.valueCstRef);
                if (!cst.isInt())
                    continue;

                outValue = static_cast<uint32_t>(cst.getInt().as64());
                return true;
            }
        }

        return false;
    }

    bool tryGetFieldAlignAttributeValue(uint32_t& outValue, TaskContext& ctx, const SymbolStruct& owner, const SymbolVariable& field)
    {
        outValue                             = 0;
        const AttributeList& fieldAttributes = field.attributes();
        const AttributeList& ownerAttributes = owner.attributes();
        const size_t         startIndex      = inheritedAttributePrefixCount(fieldAttributes, ownerAttributes);

        for (size_t i = startIndex; i < fieldAttributes.attributes.size(); ++i)
        {
            const AttributeInstance& attribute = fieldAttributes.attributes[i];
            if (!attribute.symbol || !attribute.symbol->inSwagNamespace(ctx) || attribute.symbol->name(ctx) != "Align")
                continue;

            for (const AttributeParamInstance& param : attribute.params)
            {
                if (!param.valueCstRef.isValid())
                    continue;

                const ConstantValue& cst = ctx.cstMgr().get(param.valueCstRef);
                if (!cst.isInt())
                    continue;

                outValue = static_cast<uint32_t>(cst.getInt().as64());
                return true;
            }
        }

        return false;
    }

    bool tryGetFieldOffsetAttributeValue(std::string_view& outValue, TaskContext& ctx, const SymbolStruct& owner, const SymbolVariable& field)
    {
        outValue                             = {};
        const AttributeList& fieldAttributes = field.attributes();
        const AttributeList& ownerAttributes = owner.attributes();
        const size_t         startIndex      = inheritedAttributePrefixCount(fieldAttributes, ownerAttributes);

        for (size_t i = startIndex; i < fieldAttributes.attributes.size(); ++i)
        {
            const AttributeInstance& attribute = fieldAttributes.attributes[i];
            if (!attribute.symbol || !attribute.symbol->inSwagNamespace(ctx) || attribute.symbol->name(ctx) != "Offset")
                continue;

            for (const AttributeParamInstance& param : attribute.params)
            {
                if (!param.valueCstRef.isValid())
                    continue;

                const ConstantValue& cst = ctx.cstMgr().get(param.valueCstRef);
                if (!cst.isString())
                    continue;

                outValue = cst.getString();
                return true;
            }
        }

        return false;
    }

    const SymbolVariable* findOffsetTargetField(const TaskContext& ctx, const SymbolStruct& owner, const SymbolVariable& field, std::string_view targetName)
    {
        for (const SymbolVariable* candidate : owner.fields())
        {
            if (!candidate)
                continue;
            if (candidate == &field)
                break;
            if (candidate->name(ctx) == targetName)
                return candidate;
        }

        return nullptr;
    }

    uint32_t effectiveFieldAlignment(TaskContext& ctx, const SymbolStruct& owner, const SymbolVariable& field, const uint32_t structPack)
    {
        const TypeInfo& fieldType = field.typeInfo(ctx);
        uint32_t        alignOf   = std::max<uint32_t>(fieldType.alignOf(ctx), 1);

        if (structPack != 0)
            alignOf = std::min(alignOf, structPack);

        uint32_t fieldAlign = 0;
        if (tryGetFieldAlignAttributeValue(fieldAlign, ctx, owner, field) && fieldAlign != 0)
            alignOf = std::max(alignOf, fieldAlign);

        return std::max<uint32_t>(alignOf, 1);
    }

    bool resolveUsingFieldPathRec(const TaskContext& ctx, const SymbolStruct& currentStruct, const SymbolStruct& targetStruct, SmallVector<SymbolStructUsingPathStep>& outSteps, SmallVector<const SymbolStruct*>& visited)
    {
        if (&currentStruct == &targetStruct)
            return true;

        for (const SymbolStruct* visitedStruct : visited)
        {
            if (visitedStruct == &currentStruct)
                return false;
        }

        visited.push_back(&currentStruct);
        for (const SymbolVariable* field : currentStruct.fields())
        {
            if (!field || !field->isUsingField())
                continue;

            bool                usingFieldIsPointer = false;
            const SymbolStruct* usingTargetStruct   = field->usingTargetStruct(ctx, usingFieldIsPointer);
            if (!usingTargetStruct)
                continue;

            outSteps.push_back({.field = field, .isPointer = usingFieldIsPointer});
            if (resolveUsingFieldPathRec(ctx, *usingTargetStruct, targetStruct, outSteps, visited))
                return true;
            outSteps.pop_back();
        }

        return false;
    }

    struct GenericEvalBindingKey
    {
        IdentifierRef idRef;
        AstNodeRef    exprRef;
        TypeRef       typeRef = TypeRef::invalid();
        ConstantRef   cstRef  = ConstantRef::invalid();
    };

    struct GenericEvalEntry
    {
        const Ast*                         ownerAst  = nullptr;
        AstNodeRef                         sourceRef = AstNodeRef::invalid();
        std::vector<GenericEvalBindingKey> bindings;
        AstNodeRef                         evalRef = AstNodeRef::invalid();
    };

    bool sameGenericEvalBindings(std::span<const GenericEvalBindingKey> lhs, std::span<const SemaClone::ParamBinding> rhs)
    {
        if (lhs.size() != rhs.size())
            return false;

        for (size_t i = 0; i < lhs.size(); ++i)
        {
            if (lhs[i].idRef != rhs[i].idRef ||
                lhs[i].exprRef != rhs[i].exprRef ||
                lhs[i].typeRef != rhs[i].typeRef ||
                lhs[i].cstRef != rhs[i].cstRef)
                return false;
        }

        return true;
    }

    void copyGenericEvalBindings(std::vector<GenericEvalBindingKey>& out, std::span<const SemaClone::ParamBinding> bindings)
    {
        out.clear();
        out.reserve(bindings.size());
        for (const auto& binding : bindings)
        {
            out.push_back({.idRef = binding.idRef, .exprRef = binding.exprRef, .typeRef = binding.typeRef, .cstRef = binding.cstRef});
        }
    }

    bool sameInterfaceImplementation(const SymbolImpl& lhs, const SymbolImpl& rhs)
    {
        if (const SymbolInterface* lhsInterface = lhs.symInterface())
        {
            if (const SymbolInterface* rhsInterface = rhs.symInterface())
                return lhsInterface == rhsInterface;
        }

        return lhs.idRef() == rhs.idRef();
    }
}

void SymbolStruct::addImpl(Sema& sema, SymbolImpl& symImpl)
{
    const std::unique_lock lk(mutexImpls_);

    if (std::ranges::find(impls_, &symImpl) != impls_.end())
    {
        symImpl.setSymStruct(this);
        return;
    }

    symImpl.setSymStruct(this);
    impls_.push_back(&symImpl);
    sema.compiler().notifyAlive();
}

std::vector<SymbolImpl*> SymbolStruct::impls() const
{
    const std::shared_lock lk(mutexImpls_);
    return impls_;
}

std::vector<SymbolFunction*> SymbolStruct::declaredMethods() const
{
    std::vector<SymbolFunction*> result;
    appendImplFunctions(result, impls());
    appendImplFunctions(result, interfaces());
    std::ranges::sort(result, compareFunctionOrder);
    return result;
}

std::vector<SymbolFunction*> SymbolStruct::methods() const
{
    // Generic roots are marked sema-complete before their impl methods are specialized.
    // Exporting runtime method reflection from that state can observe signatures that still
    // depend on the owner generic context and have no stable runtime function type yet.
    if (isGenericRoot() && !isGenericInstance())
        return {};

    std::vector<SymbolFunction*> result;
    for (SymbolFunction* symFunc : declaredMethods())
    {
        if (!symFunc || !isRuntimeReflectedMethod(*symFunc))
            continue;
        result.push_back(symFunc);
    }

    std::ranges::sort(result, compareFunctionOrder);
    return result;
}

void SymbolStruct::addInterface(SymbolImpl& symImpl)
{
    const std::unique_lock lk(mutexInterfaces_);

    if (std::ranges::find(interfaces_, &symImpl) != interfaces_.end())
    {
        symImpl.setSymStruct(this);
        return;
    }

    symImpl.setSymStruct(this);
    interfaces_.push_back(&symImpl);
}

Result SymbolStruct::addInterface(Sema& sema, SymbolImpl& symImpl)
{
    const std::unique_lock lk(mutexInterfaces_);
    for (const auto* itf : interfaces_)
    {
        if (itf == &symImpl)
        {
            symImpl.setSymStruct(this);
            return Result::Continue;
        }

        if (sameInterfaceImplementation(*itf, symImpl))
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_interface_already_implemented, symImpl);
            if (const SymbolInterface* symInterface = symImpl.symInterface())
                diag.addArgument(Diagnostic::ARG_SYM, symInterface->getFullScopedName(sema.ctx()));
            diag.addArgument(Diagnostic::ARG_WHAT, name(sema.ctx()));
            auto&             note    = diag.addElement(DiagnosticId::sema_note_other_implementation);
            const SourceView& srcView = sema.compiler().srcView(itf->srcViewRef());
            note.setSrcView(&srcView);
            note.addSpan(srcView.tokenCodeRange(sema.ctx(), itf->tokRef()), "");
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    // Expose the interface implementation scope under the struct symbol map so we can resolve
    // `StructName.InterfaceName.Symbol`.
    const Symbol* inserted = addSingleSymbol(sema.ctx(), &symImpl);
    if (inserted != &symImpl)
        return SemaError::raiseAlreadyDefined(sema, &symImpl, inserted);

    symImpl.setSymStruct(this);
    interfaces_.push_back(&symImpl);
    sema.compiler().notifyAlive();
    return Result::Continue;
}

std::vector<SymbolImpl*> SymbolStruct::interfaces() const
{
    const std::shared_lock lk(mutexInterfaces_);
    return interfaces_;
}

void SymbolStruct::removeIgnoredFields()
{
    std::erase_if(fields_, std::mem_fn(&Symbol::isIgnored));
}

ConstantRef SymbolStruct::computeDefaultValue(Sema& sema, TypeRef typeRef)
{
    std::call_once(defaultStructOnce_, [&] {
        auto            ctx        = sema.ctx();
        const TypeInfo& ty         = type(ctx);
        uint64_t        structSize = ty.sizeOf(ctx);
        if (!structSize)
        {
            SWC_INTERNAL_CHECK(computeLayout(ctx) == Result::Continue);
            structSize = ty.sizeOf(ctx);
        }
        SWC_ASSERT(structSize);
        std::vector<std::byte> buffer(structSize);
        const ByteSpanRW       bytes = asByteSpan(buffer);
        SWC_INTERNAL_CHECK(lowerImplicitDefaultBytes(sema, bytes, typeRef) == Result::Continue);
        defaultStructCst_ = ConstantHelpers::materializeStaticPayloadConstant(sema, typeRef, ByteSpan{bytes.data(), bytes.size()});
        SWC_ASSERT(defaultStructCst_.isValid());
    });

    return defaultStructCst_;
}

namespace
{
    constexpr uint32_t K_GENERIC_COMPLETION_DEPTH_MASK = 0x7FFFFFFFu;
    constexpr uint32_t K_GENERIC_NODE_COMPLETED_MASK   = 1u << 31;
}

struct SymbolStruct::GenericData
{
    // Keep generic-only state off the main symbol so non-generic structs stay compact.
    GenericInstanceStorage          instances;
    std::atomic<const TaskContext*> completionOwner = nullptr;
    mutable std::atomic<uint32_t>   completionState = 0;
    SymbolStruct*                   rootSym         = nullptr;
    mutable std::mutex              evalCacheMutex;
    std::vector<GenericEvalEntry>   evalCache;
};

const SymbolImpl* SymbolStruct::findInterfaceImpl(IdentifierRef interfaceIdRef) const
{
    for (const auto* itfImpl : interfaces())
    {
        if (itfImpl && itfImpl->idRef() == interfaceIdRef)
            return itfImpl;
    }

    return nullptr;
}

bool SymbolStruct::implementsInterface(const SymbolInterface& itf) const
{
    SWC_ASSERT(isSemaCompleted());
    return findInterfaceImpl(itf.idRef()) != nullptr;
}

bool SymbolStruct::implementsInterfaceOrUsingFields(Sema& sema, const SymbolInterface& itf) const
{
    if (implementsInterface(itf))
        return true;

    for (const Symbol* field : fields_)
    {
        if (!field)
            continue;

        const auto& symVar = field->cast<SymbolVariable>();
        if (!symVar.isUsingField())
            continue;

        const SymbolStruct* targetStruct = symVar.usingTargetStruct(sema.ctx());
        if (targetStruct && targetStruct->implementsInterface(itf))
            return true;
    }

    return false;
}

bool SymbolStruct::resolveUsingFieldPath(const TaskContext& ctx, const SymbolStruct& targetStruct, SmallVector<SymbolStructUsingPathStep>& outSteps) const
{
    outSteps.clear();
    SmallVector<const SymbolStruct*> visited;
    return resolveUsingFieldPathRec(ctx, *this, targetStruct, outSteps, visited);
}

Result SymbolStruct::canBeCompleted(Sema& sema) const
{
    for (const auto* field : fields_)
    {
        auto& symVar = field->cast<SymbolVariable>();

        const AstNode* decl = symVar.decl();
        SWC_ASSERT(decl != nullptr);
        SWC_ASSERT(decl->is(AstNodeId::SingleVarDecl) || decl->is(AstNodeId::MultiVarDecl));
        const auto& type        = symVar.typeInfo(sema.ctx());
        AstNodeRef  typeNodeRef = AstNodeRef::invalid();
        if (decl->is(AstNodeId::SingleVarDecl))
            typeNodeRef = decl->cast<AstSingleVarDecl>().typeOrInitRef();
        else if (decl->is(AstNodeId::MultiVarDecl))
            typeNodeRef = decl->cast<AstMultiVarDecl>().typeOrInitRef();
        else
            SWC_UNREACHABLE();

        // A struct is referencing itself
        if (type.isStruct() && &type.payloadSymStruct() == this)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_struct_circular_reference, typeNodeRef);
            diag.addArgument(Diagnostic::ARG_VALUE, symVar.name(sema.ctx()));
            diag.addArgument(Diagnostic::ARG_SYM, name(sema.ctx()));
            diag.report(sema.ctx());
            return Result::Error;
        }

        // Function values have pointer/closure storage. Their parameter and return
        // types do not affect the enclosing struct layout, and waiting for them can
        // create false cycles for signatures such as `func(Self)`.
        if (!type.isFunction())
            SWC_RESULT(sema.waitSemaCompleted(&type, typeNodeRef));
    }

    return Result::Continue;
}

AstNodeRef SymbolStruct::findGenericEvalNode(const Ast& ownerAst, const AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings) const
{
    const auto&            data = ensureGenericData();
    const std::scoped_lock lock(data.evalCacheMutex);
    for (const auto& entry : data.evalCache)
    {
        if (entry.ownerAst != &ownerAst)
            continue;
        if (entry.sourceRef != sourceRef)
            continue;
        if (!sameGenericEvalBindings(entry.bindings, bindings))
            continue;

        return entry.evalRef;
    }

    return AstNodeRef::invalid();
}

void SymbolStruct::cacheGenericEvalNode(const Ast& ownerAst, const AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, const AstNodeRef evalRef) const
{
    if (sourceRef.isInvalid() || evalRef.isInvalid())
        return;

    auto&                  data = ensureGenericData();
    const std::scoped_lock lock(data.evalCacheMutex);
    for (auto& entry : data.evalCache)
    {
        if (entry.ownerAst != &ownerAst)
            continue;
        if (entry.sourceRef != sourceRef)
            continue;
        if (!sameGenericEvalBindings(entry.bindings, bindings))
            continue;

        entry.evalRef = evalRef;
        return;
    }

    auto& newEntry     = data.evalCache.emplace_back();
    newEntry.ownerAst  = &ownerAst;
    newEntry.sourceRef = sourceRef;
    newEntry.evalRef   = evalRef;
    copyGenericEvalBindings(newEntry.bindings, bindings);
}

Result SymbolStruct::registerSpecOps(Sema& sema) const
{
    for (const SymbolImpl* symImpl : impls())
    {
        if (symImpl->isIgnored())
            continue;
        for (SymbolFunction* symFunc : symImpl->specOps())
        {
            if (!symFunc)
                continue;
            if (symFunc->isGenericRoot() && !symFunc->isGenericInstance())
                continue;
            SWC_RESULT(SemaSpecOp::registerSymbol(sema, *symFunc));
        }
    }

    return Result::Continue;
}

void SymbolStruct::addField(SymbolVariable* sym)
{
    SWC_ASSERT(sym != nullptr);
    fields_.push_back(sym);
}

Result SymbolStruct::computeLayout(TaskContext& ctx)
{
    sizeInBytes_         = 0;
    alignment_           = 1;
    uint32_t structPack  = 0;
    uint32_t structAlign = 0;
    tryGetSwagLayoutAttributeValue(structPack, ctx, attributes(), "Pack");
    tryGetSwagLayoutAttributeValue(structAlign, ctx, attributes(), "Align");

    for (SymbolVariable* field : fields_)
    {
        auto&       symVar = field->cast<SymbolVariable>();
        const auto& type   = symVar.typeInfo(ctx);

        const uint64_t sizeOf  = type.sizeOf(ctx);
        const uint32_t alignOf = effectiveFieldAlignment(ctx, *this, symVar, structPack);
        alignment_             = std::max(alignment_, alignOf);

        if (isUnion())
        {
            symVar.setOffset(0);
            sizeInBytes_ = std::max(sizeInBytes_, sizeOf);
        }
        else
        {
            std::string_view      offsetTargetName;
            const SymbolVariable* offsetTarget = nullptr;
            uint64_t              fieldOffset  = sizeInBytes_;
            if (tryGetFieldOffsetAttributeValue(offsetTargetName, ctx, *this, symVar))
            {
                offsetTarget = findOffsetTargetField(ctx, *this, symVar, offsetTargetName);
                SWC_ASSERT(offsetTarget != nullptr);
                if (offsetTarget)
                    fieldOffset = offsetTarget->offset();
            }
            else
            {
                const uint64_t padding = (alignOf - (sizeInBytes_ % alignOf)) % alignOf;
                fieldOffset            = sizeInBytes_ + padding;
            }

            symVar.setOffset(static_cast<uint32_t>(fieldOffset));
            sizeInBytes_ = std::max(sizeInBytes_, fieldOffset + sizeOf);
        }
    }

    if (structAlign != 0)
        alignment_ = std::max(alignment_, structAlign);

    if (alignment_ > 0)
    {
        const uint64_t padding = (alignment_ - (sizeInBytes_ % alignment_)) % alignment_;
        sizeInBytes_ += padding;
    }

    sizeInBytes_ = std::max(sizeInBytes_, 1ULL);

    return Result::Continue;
}

SmallVector<SymbolFunction*> SymbolStruct::getSpecOp(IdentifierRef identifierRef) const
{
    SmallVector<SymbolFunction*> result;

    const std::shared_lock lk(mutexSpecOps_);
    for (SymbolFunction* symFunc : specOps_)
    {
        if (symFunc->idRef() == identifierRef)
            result.push_back(symFunc);
    }

    return result;
}

Result SymbolStruct::registerSpecOp(SymbolFunction& symFunc, SpecOpKind kind)
{
    const std::unique_lock lk(mutexSpecOps_);
    if (std::ranges::find(specOps_, &symFunc) != specOps_.end())
        return Result::Continue;
    specOps_.push_back(&symFunc);

    switch (kind)
    {
        case SpecOpKind::OpDrop:
            SWC_ASSERT(!opDrop_);
            opDrop_ = &symFunc;
            break;
        case SpecOpKind::OpPostCopy:
            SWC_ASSERT(!opPostCopy_);
            opPostCopy_ = &symFunc;
            break;
        case SpecOpKind::OpPostMove:
            SWC_ASSERT(!opPostMove_);
            opPostMove_ = &symFunc;
            break;
        default:
            break;
    }

    return Result::Continue;
}

SymbolFunction* SymbolStruct::effectiveOpDrop(TaskContext& ctx)
{
    return const_cast<SymbolFunction*>(const_cast<const SymbolStruct*>(this)->effectiveOpDrop(ctx));
}

SymbolFunction* SymbolStruct::effectiveOpInit(TaskContext& ctx)
{
    return const_cast<SymbolFunction*>(const_cast<const SymbolStruct*>(this)->effectiveOpInit(ctx));
}

const SymbolFunction* SymbolStruct::effectiveOpInit(TaskContext& ctx) const
{
    if (isGenericRoot() && !isGenericInstance())
        return nullptr;

    return findGeneratedInitWrapper(ctx, *this);
}

const SymbolFunction* SymbolStruct::effectiveOpDrop(TaskContext& ctx) const
{
    if (isGenericRoot() && !isGenericInstance())
        return nullptr;

    if (const SymbolFunction* wrapper = findGeneratedLifecycleWrapper(ctx, *this, SpecOpKind::OpDrop))
        return wrapper;

    return resolvedLifecycleFunction(ctx, *this, SpecOpKind::OpDrop);
}

SymbolFunction* SymbolStruct::effectiveOpPostCopy(TaskContext& ctx)
{
    return const_cast<SymbolFunction*>(const_cast<const SymbolStruct*>(this)->effectiveOpPostCopy(ctx));
}

const SymbolFunction* SymbolStruct::effectiveOpPostCopy(TaskContext& ctx) const
{
    if (isGenericRoot() && !isGenericInstance())
        return nullptr;

    if (const SymbolFunction* wrapper = findGeneratedLifecycleWrapper(ctx, *this, SpecOpKind::OpPostCopy))
        return wrapper;

    return resolvedLifecycleFunction(ctx, *this, SpecOpKind::OpPostCopy);
}

SymbolFunction* SymbolStruct::effectiveOpPostMove(TaskContext& ctx)
{
    return const_cast<SymbolFunction*>(const_cast<const SymbolStruct*>(this)->effectiveOpPostMove(ctx));
}

const SymbolFunction* SymbolStruct::effectiveOpPostMove(TaskContext& ctx) const
{
    if (isGenericRoot() && !isGenericInstance())
        return nullptr;

    if (const SymbolFunction* wrapper = findGeneratedLifecycleWrapper(ctx, *this, SpecOpKind::OpPostMove))
        return wrapper;

    return resolvedLifecycleFunction(ctx, *this, SpecOpKind::OpPostMove);
}

void SymbolStruct::setGenericRoot(bool value) noexcept
{
    if (value)
        addExtraFlag(SymbolStructFlagsE::GenericRoot);
    else
        removeExtraFlag(SymbolStructFlagsE::GenericRoot);
}

void SymbolStruct::setGenericInstance(SymbolStruct* root) noexcept
{
    if (root)
    {
        addExtraFlag(SymbolStructFlagsE::GenericInstance);
        ensureGenericData().rootSym = root;
    }
    else
    {
        removeExtraFlag(SymbolStructFlagsE::GenericInstance);
        if (auto* data = genericData())
            data->rootSym = nullptr;
    }
}

SymbolStruct* SymbolStruct::genericRootSym() noexcept
{
    if (const auto* data = genericData())
        return data->rootSym;
    return nullptr;
}

const SymbolStruct* SymbolStruct::genericRootSym() const noexcept
{
    if (const auto* data = genericData())
        return data->rootSym;
    return nullptr;
}

SymbolStruct::GenericData* SymbolStruct::genericData() const noexcept
{
    return genericData_.load(std::memory_order_acquire);
}

SymbolStruct::GenericData& SymbolStruct::ensureGenericData() const noexcept
{
    if (auto* data = genericData())
        return *data;

    auto* newData  = heapNew<GenericData>();
    auto* expected = static_cast<GenericData*>(nullptr);
    if (!genericData_.compare_exchange_strong(expected, newData, std::memory_order_acq_rel, std::memory_order_acquire))
    {
        heapDelete(newData);
        return *expected;
    }

    return *newData;
}

GenericInstanceStorage& SymbolStruct::genericInstanceStorage() noexcept
{
    return ensureGenericData().instances;
}

const GenericInstanceStorage& SymbolStruct::genericInstanceStorage() const noexcept
{
    const auto* data = genericData();
    SWC_ASSERT(data != nullptr);
    return data->instances;
}

bool SymbolStruct::tryGetGenericInstanceArgs(const SymbolStruct& instance, SmallVector<GenericInstanceKey>& outArgs) const
{
    if (const auto* data = genericData())
        return data->instances.tryGetArgs(instance, outArgs);
    return false;
}

void SymbolStruct::setGenericCompletionOwner(const TaskContext& ctx) const noexcept
{
    auto&              data     = ensureGenericData();
    const TaskContext* expected = nullptr;
    const bool         done     = data.completionOwner.compare_exchange_strong(expected, &ctx, std::memory_order_acq_rel);
    SWC_ASSERT(done || expected == &ctx);
}

bool SymbolStruct::isGenericCompletionOwner(const TaskContext& ctx) const noexcept
{
    const auto* data = genericData();
    return data && data->completionOwner.load(std::memory_order_acquire) == &ctx;
}

bool SymbolStruct::tryStartGenericCompletion(const TaskContext& ctx) const noexcept
{
    SWC_ASSERT(isGenericCompletionOwner(ctx));
    const auto* data = genericData();
    SWC_ASSERT(data != nullptr);
    const auto previousState = data->completionState.fetch_add(1, std::memory_order_acq_rel);
    SWC_ASSERT((previousState & K_GENERIC_COMPLETION_DEPTH_MASK) != K_GENERIC_COMPLETION_DEPTH_MASK);
    if ((previousState & K_GENERIC_COMPLETION_DEPTH_MASK) != 0)
    {
        data->completionState.fetch_sub(1, std::memory_order_acq_rel);
        return false;
    }

    return true;
}

void SymbolStruct::finishGenericCompletion() const noexcept
{
    const auto* data = genericData();
    SWC_ASSERT(data != nullptr);
    const auto previousState = data->completionState.fetch_sub(1, std::memory_order_acq_rel);
    SWC_ASSERT((previousState & K_GENERIC_COMPLETION_DEPTH_MASK) != 0);
}

bool SymbolStruct::isGenericNodeCompleted() const noexcept
{
    const auto* data = genericData();
    return data && (data->completionState.load(std::memory_order_acquire) & K_GENERIC_NODE_COMPLETED_MASK) != 0;
}

void SymbolStruct::setGenericNodeCompleted() const noexcept
{
    const auto* data = genericData();
    SWC_ASSERT(data != nullptr);
    data->completionState.fetch_or(K_GENERIC_NODE_COMPLETED_MASK, std::memory_order_acq_rel);
}

bool SymbolStruct::tryMarkGeneratedLifecycleFunctions() const noexcept
{
    bool expected = false;
    return generatedLifecycleDone_.compare_exchange_strong(expected, true, std::memory_order_acq_rel, std::memory_order_acquire);
}

bool SymbolStruct::tryMarkGeneratedOperators() const noexcept
{
    bool expected = false;
    return generatedOperatorsDone_.compare_exchange_strong(expected, true, std::memory_order_acq_rel, std::memory_order_acquire);
}

SWC_END_NAMESPACE();
