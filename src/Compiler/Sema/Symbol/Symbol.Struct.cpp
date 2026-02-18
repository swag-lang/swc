#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

void SymbolStruct::addImpl(Sema& sema, SymbolImpl& symImpl)
{
    std::unique_lock lk(mutexImpls_);
    symImpl.setSymStruct(this);
    impls_.push_back(&symImpl);
    sema.compiler().notifyAlive();
}

std::vector<SymbolImpl*> SymbolStruct::impls() const
{
    std::shared_lock lk(mutexImpls_);
    return impls_;
}

void SymbolStruct::addInterface(SymbolImpl& symImpl)
{
    std::unique_lock lk(mutexInterfaces_);
    symImpl.setSymStruct(this);
    interfaces_.push_back(&symImpl);
}

Result SymbolStruct::addInterface(Sema& sema, SymbolImpl& symImpl)
{
    std::unique_lock lk(mutexInterfaces_);
    for (const auto itf : interfaces_)
    {
        if (itf->idRef() == symImpl.idRef())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_interface_already_implemented, symImpl);
            diag.addArgument(Diagnostic::ARG_WHAT, name(sema.ctx()));
            auto&       note    = diag.addElement(DiagnosticId::sema_note_other_implementation);
            const auto& srcView = sema.compiler().srcView(itf->srcViewRef());
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
    std::shared_lock lk(mutexInterfaces_);
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
        const std::vector<std::byte> buffer(structSize);
        const ByteSpan               bytes = asByteSpan(buffer);
        ConstantLower::lowerAggregateStructToBytes(sema, bytes, ty, {});
        const ConstantValue cstVal = ConstantValue::makeStruct(ctx, typeRef, bytes);
        defaultStructCst_          = sema.cstMgr().addConstant(ctx, cstVal);
    });

    return defaultStructCst_;
}

namespace
{
    bool isUsingMemberDecl(const AstNode* decl)
    {
        if (!decl)
            return false;
        if (const AstSingleVarDecl* var = decl->safeCast<AstSingleVarDecl>())
            return var->hasFlag(AstVarDeclFlagsE::Using);
        if (const AstMultiVarDecl* varList = decl->safeCast<AstMultiVarDecl>())
            return varList->hasFlag(AstVarDeclFlagsE::Using);
        return false;
    }
}

bool SymbolStruct::implementsInterface(const SymbolInterface& itf) const
{
    SWC_ASSERT(isSemaCompleted());
    for (const auto itfImpl : interfaces())
    {
        if (itfImpl && itfImpl->idRef() == itf.idRef())
            return true;
    }

    return false;
}

bool SymbolStruct::implementsInterfaceOrUsingFields(Sema& sema, const SymbolInterface& itf) const
{
    if (implementsInterface(itf))
        return true;

    const TaskContext& ctx = sema.ctx();
    const auto& typeMgr = sema.typeMgr();

    for (const Symbol* field : fields_)
    {
        if (!field)
            continue;

        const auto& symVar = field->cast<SymbolVariable>();
        if (!isUsingMemberDecl(symVar.decl()))
            continue;

        const TypeRef   ultimateTypeRef = typeMgr.get(symVar.typeRef()).unwrap(ctx, symVar.typeRef(), TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo& ultimateType    = typeMgr.get(ultimateTypeRef);

        if (ultimateType.isStruct())
        {
            if (ultimateType.payloadSymStruct().implementsInterface(itf))
                return true;
            continue;
        }

        if (ultimateType.isAnyPointer())
        {
            const TypeRef   pointeeUltimateRef = typeMgr.get(ultimateType.payloadTypeRef()).unwrap(ctx, ultimateType.payloadTypeRef(), TypeExpandE::Alias | TypeExpandE::Enum);
            const TypeInfo& pointeeUltimate    = typeMgr.get(pointeeUltimateRef);
            if (pointeeUltimate.isStruct() && pointeeUltimate.payloadSymStruct().implementsInterface(itf))
                return true;
        }
    }

    return false;
}

Result SymbolStruct::canBeCompleted(Sema& sema) const
{
    for (const auto field : fields_)
    {
        auto& symVar = field->cast<SymbolVariable>();

        SWC_ASSERT(symVar.decl()->is(AstNodeId::SingleVarDecl) || symVar.decl()->is(AstNodeId::MultiVarDecl));
        auto&      type        = symVar.typeInfo(sema.ctx());
        AstNodeRef typeNodeRef = AstNodeRef::invalid();
        if (const AstSingleVarDecl* varSingle = symVar.decl()->safeCast<AstSingleVarDecl>())
            typeNodeRef = varSingle->typeOrInitRef();
        else if (const AstMultiVarDecl* varMulti = symVar.decl()->safeCast<AstMultiVarDecl>())
            typeNodeRef = varMulti->typeOrInitRef();
        else
            SWC_UNREACHABLE();

        // A struct is referencing itself
        if (type.isStruct() && &type.payloadSymStruct() == this)
            return SemaError::raise(sema, DiagnosticId::sema_err_struct_circular_reference, typeNodeRef);

        RESULT_VERIFY(sema.waitSemaCompleted(&type, typeNodeRef));
    }

    return Result::Continue;
}

Result SymbolStruct::registerSpecOps(Sema& sema) const
{
    for (const SymbolImpl* symImpl : impls())
    {
        if (!symImpl)
            continue;
        for (SymbolFunction* symFunc : symImpl->specOps())
        {
            if (!symFunc)
                continue;
            RESULT_VERIFY(SemaSpecOp::registerSymbol(sema, *symFunc));
        }
    }

    return Result::Continue;
}

Result SymbolStruct::computeLayout(TaskContext& ctx)
{
    sizeInBytes_ = 0;
    alignment_   = 1;

    for (const auto field : fields_)
    {
        auto& symVar = field->cast<SymbolVariable>();
        auto& type   = symVar.typeInfo(ctx);

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

    std::shared_lock lk(mutexSpecOps_);
    for (SymbolFunction* symFunc : specOps_)
    {
        if (symFunc->idRef() == identifierRef)
            result.push_back(symFunc);
    }

    return result;
}

Result SymbolStruct::registerSpecOp(SymbolFunction& symFunc, SpecOpKind kind)
{
    std::unique_lock lk(mutexSpecOps_);
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

SWC_END_NAMESPACE();
