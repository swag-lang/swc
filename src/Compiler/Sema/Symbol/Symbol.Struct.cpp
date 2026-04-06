#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_STATS
namespace
{
    template<typename T>
    size_t vectorStorageReserved(const std::vector<T>& values)
    {
        return values.capacity() * sizeof(T);
    }
}
#endif

void SymbolStruct::addImpl(Sema& sema, SymbolImpl& symImpl)
{
    const std::unique_lock lk(mutexImpls_);
    symImpl.setSymStruct(this);
    impls_.push_back(&symImpl);
    sema.compiler().notifyAlive();
}

std::vector<SymbolImpl*> SymbolStruct::impls() const
{
    const std::shared_lock lk(mutexImpls_);
    return impls_;
}

void SymbolStruct::addInterface(SymbolImpl& symImpl)
{
    const std::unique_lock lk(mutexInterfaces_);
    symImpl.setSymStruct(this);
    interfaces_.push_back(&symImpl);
}

Result SymbolStruct::addInterface(Sema& sema, SymbolImpl& symImpl)
{
    const std::unique_lock lk(mutexInterfaces_);
    for (const auto* itf : interfaces_)
    {
        if (itf->idRef() == symImpl.idRef())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_interface_already_implemented, symImpl);
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
    if (const Symbol* inserted = addSingleSymbol(sema.ctx(), &symImpl); inserted != &symImpl)
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
    fields_.erase(std::ranges::remove_if(fields_, [](const Symbol* field) {
                      return field->isIgnored();
                  }).begin(),
                  fields_.end());
}

ConstantRef SymbolStruct::computeDefaultValue(Sema& sema, TypeRef typeRef)
{
    std::call_once(defaultStructOnce_, [&] {
        auto            ctx        = sema.ctx();
        const TypeInfo& ty         = type(ctx);
        const uint64_t  structSize = ty.sizeOf(ctx);
        SWC_ASSERT(structSize);
        std::vector<std::byte> buffer(structSize);
        const ByteSpanRW       bytes = asByteSpan(buffer);
        SWC_INTERNAL_CHECK(ConstantLower::lowerAggregateStructToBytes(sema, bytes, ty, {}) == Result::Continue);
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

        SWC_RESULT(sema.waitSemaCompleted(&type, typeNodeRef));
    }

    return Result::Continue;
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
    sizeInBytes_ = 0;
    alignment_   = 1;

    for (SymbolVariable* field : fields_)
    {
        auto&       symVar = field->cast<SymbolVariable>();
        const auto& type   = symVar.typeInfo(ctx);

        const uint64_t sizeOf  = type.sizeOf(ctx);
        const uint32_t alignOf = type.alignOf(ctx);
        alignment_             = std::max(alignment_, alignOf);

        const uint64_t padding = (alignOf - (sizeInBytes_ % alignOf)) % alignOf;
        sizeInBytes_ += padding;

        symVar.setOffset(static_cast<uint32_t>(sizeInBytes_));
        sizeInBytes_ += sizeOf;
    }

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

void SymbolStruct::setGenericCompletionOwner(const TaskContext& ctx) noexcept
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

SWC_END_NAMESPACE();
