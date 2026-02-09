#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
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
    if (const auto* inserted = addSingleSymbol(sema.ctx(), &symImpl); inserted != &symImpl)
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
    fields_.erase(std::ranges::remove_if(fields_, [](const auto* field) {
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
        if (const auto* var = decl->safeCast<AstSingleVarDecl>())
            return var->hasFlag(AstVarDeclFlagsE::Using);
        if (const auto* varList = decl->safeCast<AstMultiVarDecl>())
            return varList->hasFlag(AstVarDeclFlagsE::Using);
        return false;
    }
}

bool SymbolStruct::implementsInterface(const SymbolInterface& itf) const
{
    SWC_ASSERT(isCompleted());
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

    const auto& ctx     = sema.ctx();
    const auto& typeMgr = sema.typeMgr();

    for (const auto* field : fields_)
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
        auto&            type        = symVar.typeInfo(sema.ctx());
        const auto       var         = reinterpret_cast<const AstVarDeclBase*>(symVar.decl());
        const AstNodeRef typeNodeRef = var->typeOrInitRef();

        // A struct is referencing itself
        if (type.isStruct() && &type.payloadSymStruct() == this)
            return SemaError::raise(sema, DiagnosticId::sema_err_struct_circular_reference, typeNodeRef);

        RESULT_VERIFY(sema.waitCompleted(&type, typeNodeRef));
    }

    return Result::Continue;
}

void SymbolStruct::computeLayout(Sema& sema)
{
    auto& ctx = sema.ctx();

    sizeInBytes_ = 0;
    alignment_   = 1;

    for (const auto field : fields_)
    {
        auto& symVar = field->cast<SymbolVariable>();

        auto& type = symVar.typeInfo(ctx);

        const auto sizeOf  = type.sizeOf(ctx);
        const auto alignOf = type.alignOf(ctx);
        alignment_         = std::max(alignment_, alignOf);

        const auto padding = (alignOf - (sizeInBytes_ % alignOf)) % alignOf;
        sizeInBytes_ += padding;

        symVar.setOffset(static_cast<uint32_t>(sizeInBytes_));
        sizeInBytes_ += sizeOf;
    }

    if (alignment_ > 0)
    {
        const auto padding = (alignment_ - (sizeInBytes_ % alignment_)) % alignment_;
        sizeInBytes_ += padding;
    }
}

namespace
{
    bool allowsSpecialFunctionOverload(SpecOpKind kind)
    {
        switch (kind)
        {
            case SpecOpKind::OpCast:
            case SpecOpKind::OpEquals:
            case SpecOpKind::OpCmp:
            case SpecOpKind::OpBinary:
            case SpecOpKind::OpAssign:
            case SpecOpKind::OpAffect:
            case SpecOpKind::OpAffectLiteral:
            case SpecOpKind::OpIndex:
            case SpecOpKind::OpIndexAssign:
            case SpecOpKind::OpIndexAffect:
                return true;
            default:
                return false;
        }
    }
}

Result SymbolStruct::registerSpecOp(Sema& sema, SymbolFunction& symFunc, SpecOpKind kind)
{
    std::unique_lock lk(mutexSpecOps_);
    if (std::ranges::find(specOps_, &symFunc) != specOps_.end())
        return Result::Continue;

    const IdentifierRef idRef = symFunc.idRef();
    if (!allowsSpecialFunctionOverload(kind))
    {
        for (const auto* existing : specOps_)
        {
            if (existing && existing->idRef() == idRef)
            {
                SemaError::raiseAlreadyDefined(sema, &symFunc, existing);
                return Result::Error;
            }
        }
    }

    const auto& idMgr = sema.idMgr();
    if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpDrop))
        opDrop_ = &symFunc;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpPostCopy))
        opPostCopy_ = &symFunc;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpPostMove))
        opPostMove_ = &symFunc;

    specOps_.push_back(&symFunc);
    return Result::Continue;
}

SWC_END_NAMESPACE();
