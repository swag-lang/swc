#include "pch.h"
#include "Compiler/Sema/Helpers/SemaTagged.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const SymbolEnum* tagEnum(Sema& sema, const SymbolStruct& tagged)
    {
        const TypeInfo& tagType = sema.typeMgr().get(tagged.taggedTypeRef()).unwrapAliasTypeOrSelf(sema.ctx());
        return tagType.isEnum() ? &tagType.payloadSymEnum() : nullptr;
    }

    template<typename F>
    void forEachCase(Sema& sema, const SymbolStruct& tagged, const F& fn)
    {
        const SymbolEnum* symEnum = tagEnum(sema, tagged);
        if (!symEnum)
            return;

        std::vector<const Symbol*> symbols;
        symEnum->getAllSymbols(symbols);
        for (const Symbol* symbol : symbols)
        {
            const auto* enumValue = symbol ? symbol->safeCast<SymbolEnumValue>() : nullptr;
            if (enumValue && enumValue->cstRef().isValid())
                fn(*enumValue);
        }
    }

    bool containsCase(std::span<const ConstantRef> cases, ConstantRef value)
    {
        return std::ranges::find(cases, value) != cases.end();
    }

    const SymbolStruct* structOfPointee(TaskContext& ctx, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return nullptr;

        const TypeInfo* type = &ctx.typeMgr().get(typeRef).unwrapAliasTypeOrSelf(ctx);
        if (type->isValuePointer() || type->isReference())
            type = &ctx.typeMgr().get(type->payloadTypeRef()).unwrapAliasTypeOrSelf(ctx);

        return type->isStruct() ? &type->payloadSymStruct() : nullptr;
    }

    // Where the union sits in a constant of 'typeRef': the value itself, or a member reached
    // through 'using' fields that hold it in place.
    bool constantUnionOffset(Sema& sema, uint64_t& outOffset, TypeRef typeRef, const SymbolStruct& tagged)
    {
        outOffset = 0;

        const TypeInfo& type = sema.typeMgr().get(typeRef).unwrapAliasTypeOrSelf(sema.ctx());
        if (!type.isStruct())
            return false;
        if (&type.payloadSymStruct() == &tagged)
            return true;

        SmallVector<SymbolStructUsingPathStep> steps;
        if (!type.payloadSymStruct().resolveUsingFieldPath(sema.ctx(), tagged, steps) || SymbolStruct::usingPathHasPointerStep(steps))
            return false;

        for (const SymbolStructUsingPathStep& step : steps)
            outOffset += step.field->offset();
        return true;
    }

    // 'u.a!' asks the runtime for the proof the flow does not have.
    bool isAssertedByParent(Sema& sema)
    {
        const AstNodeRef parentRef = sema.visit().parentNodeRef(0);
        if (parentRef.isInvalid())
            return false;

        const AstNode& parent = sema.node(parentRef);
        if (!parent.is(AstNodeId::ErrorManagementExpr) || sema.token(parent.codeRef()).id != TokenId::SymBang)
            return false;

        return parent.cast<AstErrorManagementExpr>().nodeExprRef == sema.curNodeRef();
    }
}

const SymbolStruct* SemaTagged::unionOf(TaskContext& ctx, TypeRef typeRef)
{
    if (typeRef.isInvalid())
        return nullptr;

    const TypeInfo& type = ctx.typeMgr().get(typeRef).unwrapAliasTypeOrSelf(ctx);
    if (!type.isStruct() || !type.payloadSymStruct().isTagged())
        return nullptr;

    return &type.payloadSymStruct();
}

const SymbolStruct* SemaTagged::unionOfPointee(TaskContext& ctx, TypeRef typeRef)
{
    const SymbolStruct* symStruct = structOfPointee(ctx, typeRef);
    return symStruct && symStruct->isTagged() ? symStruct : nullptr;
}

const SymbolStruct* SemaTagged::ownerUnion(const SymbolVariable& member)
{
    const SymbolMap* owner = member.ownerSymMap();
    if (!owner || !owner->isStruct())
        return nullptr;

    const auto& symStruct = owner->cast<SymbolStruct>();
    return symStruct.isTagged() ? &symStruct : nullptr;
}

uint64_t SemaTagged::valueBits(TaskContext& ctx, ConstantRef value)
{
    const ConstantValue& cst = ctx.cstMgr().get(value);
    const ConstantValue& raw = cst.isEnumValue() ? ctx.cstMgr().get(cst.getEnumValue()) : cst;
    return static_cast<uint64_t>(raw.getInt().asI64());
}

Utf8 SemaTagged::caseName(Sema& sema, const SymbolStruct& tagged, ConstantRef value)
{
    Utf8 result;
    forEachCase(sema, tagged, [&](const SymbolEnumValue& enumValue) {
        if (result.empty() && enumValue.cstRef() == value)
            result = enumValue.getFullScopedName(sema.ctx());
    });

    return result;
}

Utf8 SemaTagged::caseShortName(Sema& sema, const SymbolStruct& tagged, ConstantRef value)
{
    Utf8 result;
    forEachCase(sema, tagged, [&](const SymbolEnumValue& enumValue) {
        if (result.empty() && enumValue.cstRef() == value)
            result = enumValue.name(sema.ctx());
    });

    return result;
}

ConstantRef SemaTagged::caseFromBits(Sema& sema, const SymbolStruct& tagged, uint64_t bits)
{
    const uint32_t tagSize = tagged.taggedTagSize(sema.ctx());
    const uint64_t mask    = tagSize >= 8 ? ~0ULL : (1ULL << (tagSize * 8)) - 1;

    ConstantRef result = ConstantRef::invalid();
    forEachCase(sema, tagged, [&](const SymbolEnumValue& enumValue) {
        if (result.isInvalid() && (valueBits(sema.ctx(), enumValue.cstRef()) & mask) == (bits & mask))
            result = enumValue.cstRef();
    });

    return result;
}

Result SemaTagged::waitUnion(Sema& sema, const SymbolStruct& tagged)
{
    return sema.waitSemaCompleted(&tagged, sema.curNode().codeRef());
}

Result SemaTagged::contextUnion(Sema& sema, const SymbolStruct*& outTagged, TypeRef& outUnionTypeRef)
{
    outTagged = nullptr;

    const std::span<const TypeRef> bindingTypes = sema.frame().bindingTypes();
    if (bindingTypes.empty())
        return Result::Continue;

    const SymbolStruct* tagged = unionOf(sema.ctx(), bindingTypes.back());
    if (!tagged)
        return Result::Continue;

    SWC_RESULT(waitUnion(sema, *tagged));
    outTagged       = tagged;
    outUnionTypeRef = bindingTypes.back();
    return Result::Continue;
}

Result SemaTagged::findCase(Sema& sema, ConstantRef& outCaseRef, const SymbolStruct& tagged, IdentifierRef idRef)
{
    outCaseRef = ConstantRef::invalid();

    const TypeInfo& tagType = sema.typeMgr().get(tagged.taggedTypeRef()).unwrapAliasTypeOrSelf(sema.ctx());
    SWC_RESULT(sema.waitSemaCompleted(&tagType, sema.curNodeRef()));

    forEachCase(sema, tagged, [&](const SymbolEnumValue& enumValue) {
        if (outCaseRef.isInvalid() && enumValue.idRef() == idRef)
            outCaseRef = enumValue.cstRef();
    });

    return Result::Continue;
}

std::span<ConstantRef> SemaTagged::copyCases(Sema& sema, std::span<const ConstantRef> values)
{
    if (values.empty())
        return {};

    ConstantRef* storage = sema.compiler().allocateArray<ConstantRef>(values.size());
    std::ranges::copy(values, storage);
    return {storage, values.size()};
}

std::span<ConstantRef> SemaTagged::complementCases(Sema& sema, const SymbolStruct& tagged, std::span<const ConstantRef> values)
{
    SmallVector<ConstantRef> others;
    forEachCase(sema, tagged, [&](const SymbolEnumValue& enumValue) {
        if (!containsCase(values, enumValue.cstRef()) && !containsCase(others.span(), enumValue.cstRef()))
            others.push_back(enumValue.cstRef());
    });

    return copyCases(sema, others.span());
}

std::span<ConstantRef> SemaTagged::unionCases(Sema& sema, std::span<const ConstantRef> lhs, std::span<const ConstantRef> rhs)
{
    SmallVector<ConstantRef> merged;
    for (const ConstantRef value : lhs)
        merged.push_back(value);
    for (const ConstantRef value : rhs)
    {
        if (!containsCase(merged.span(), value))
            merged.push_back(value);
    }

    return copyCases(sema, merged.span());
}

bool SemaTagged::extractUnionPath(Sema& sema, AstNodeRef leftRef, TypeRef leftTypeRef, const SymbolStruct& tagged, SmallVector4<const Symbol*>& outPath)
{
    const SymbolStruct* leftStruct = structOfPointee(sema.ctx(), leftTypeRef);
    if (!leftStruct)
        return false;
    if (!SemaHelpers::extractNarrowPath(sema, leftRef, outPath))
        return false;
    if (leftStruct == &tagged)
        return true;

    // A payload member reached through 'using' fields belongs to the union those fields lead to.
    SmallVector<SymbolStructUsingPathStep> steps;
    if (!leftStruct->resolveUsingFieldPath(sema.ctx(), tagged, steps))
        return false;

    for (const SymbolStructUsingPathStep& step : steps)
        outPath.push_back(step.field);

    return true;
}

const SymbolStruct* SemaTagged::kindOfSubject(Sema& sema, AstNodeRef exprRef, SmallVector4<const Symbol*>& outPath)
{
    const AstNodeRef resolvedRef = sema.resolvedNodeRef(exprRef);
    if (resolvedRef.isValid())
        exprRef = resolvedRef;
    if (exprRef.isInvalid())
        return nullptr;

    const AstNode& node = sema.node(exprRef);
    if (!node.is(AstNodeId::IntrinsicCall) || node.cast<AstIntrinsicCall>().intrinsicId != TokenId::IntrinsicKindOf)
        return nullptr;

    const AstNodeRef    argRef = sema.ast().oneNode(node.cast<AstIntrinsicCall>().spanChildrenRef);
    const SymbolStruct* tagged = unionOfPointee(sema.ctx(), sema.viewType(argRef).typeRef());
    if (!tagged || !SemaHelpers::extractNarrowPath(sema, argRef, outPath))
        return nullptr;

    return tagged;
}

void SemaTagged::noteAssignedCase(Sema& sema, AstNodeRef leftRef, AstNodeRef rightRef)
{
    // A struct assigned as a whole replaces every tagged union it holds, so any case proven on
    // its path or below is gone, whatever the right side is.
    const TypeRef       leftTypeRef = sema.viewType(leftRef).typeRef();
    const SymbolStruct* tagged      = unionOf(sema.ctx(), leftTypeRef);
    if (!tagged && (!sema.anyFrameHasNarrowFacts() || !sema.typeMgr().get(leftTypeRef).unwrapAliasTypeOrSelf(sema.ctx()).isStruct()))
        return;

    SmallVector4<const Symbol*> path;
    if (!SemaHelpers::extractNarrowPath(sema, leftRef, path))
        return;

    sema.addNarrowKillAllFrames({path.data(), path.size()});
    if (!tagged)
        return;

    ConstantRef caseRef  = ConstantRef::invalid();
    AstNodeRef  valueRef = sema.resolvedNodeRef(rightRef);
    if (valueRef.isInvalid())
        valueRef = rightRef;

    if (const auto* literal = sema.node(valueRef).safeCast<AstTaggedUnionLiteral>())
        caseRef = literal->tagCstRef;
    else
    {
        const SemaNodeView view = sema.viewTypeConstant(valueRef);
        if (view.hasConstant())
            caseRef = readConstantCase(sema, *tagged, view.cstRef());
    }

    if (caseRef.isInvalid())
        return;

    const std::array oneCase{caseRef};
    sema.addNarrowCaseFactPastBindingFrames({path.data(), path.size()}, copyCases(sema, oneCase));
}

Result SemaTagged::checkPayloadAccess(Sema& sema, AstNodeRef accessRef, AstNodeRef leftRef, TypeRef leftTypeRef, const SymbolVariable& member)
{
    const SymbolStruct* tagged = ownerUnion(member);
    if (!tagged)
        return Result::Continue;

    const std::span<const ConstantRef> cases = tagged->taggedCaseValues(member);

    // A constant union, or a constant holding one through 'using' fields, names its case:
    // there is nothing left to prove.
    uint64_t           unionOffset = 0;
    const SemaNodeView leftView    = sema.viewTypeConstant(leftRef);
    if (leftView.hasConstant() && constantUnionOffset(sema, unionOffset, leftView.typeRef(), *tagged))
    {
        const ConstantRef holds = readConstantCase(sema, *tagged, leftView.cstRef(), unionOffset);
        if (holds.isValid() && containsCase(cases, holds))
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_tagged_constant_case, accessRef);
        diag.addArgument(Diagnostic::ARG_VALUE, caseName(sema, *tagged, holds));
        diag.addArgument(Diagnostic::ARG_SYM, member.name(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    SmallVector4<const Symbol*> path;
    if (extractUnionPath(sema, leftRef, leftTypeRef, *tagged, path) && sema.frame().queryNarrowCases({path.data(), path.size()}, cases))
        return Result::Continue;

    if (isAssertedByParent(sema))
    {
        SemaHelpers::ensureCodeGenLoweringPayload(sema, accessRef).taggedCaseAsserted = true;
        return SemaHelpers::setupRuntimeSafetyPanic(sema, accessRef, Runtime::SafetyWhat::Switch, sema.node(accessRef).codeRef());
    }

    auto diag = SemaError::report(sema, DiagnosticId::sema_err_tagged_payload_unproven, accessRef);
    diag.addArgument(Diagnostic::ARG_SYM, member.name(sema.ctx()));
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaTagged::checkCaseAssertion(Sema& sema, AstNodeRef childRef, bool& outHandled)
{
    outHandled = false;

    AstNodeRef resolvedRef = sema.resolvedNodeRef(childRef);
    if (resolvedRef.isInvalid())
        resolvedRef = childRef;

    const auto* lowering = sema.loweringPayload<CodeGenLoweringPayload>(resolvedRef);
    if (lowering && lowering->taggedCaseAsserted)
    {
        outHandled = true;
        return Result::Continue;
    }

    const Symbol* symbol = sema.viewSymbol(resolvedRef).singleSymbol();
    if (!symbol || !symbol->isVariable() || !ownerUnion(symbol->cast<SymbolVariable>()))
        return Result::Continue;

    auto diag = SemaError::report(sema, DiagnosticId::sema_err_tagged_case_already_proven, resolvedRef);
    diag.addArgument(Diagnostic::ARG_SYM, symbol->name(sema.ctx()));
    diag.report(sema.ctx());
    return Result::Error;
}

ConstantRef SemaTagged::readConstantCase(Sema& sema, const SymbolStruct& tagged, ConstantRef cstRef, uint64_t offset)
{
    const ConstantValue& cst = sema.cstMgr().get(cstRef);
    if (!cst.isStruct())
        return ConstantRef::invalid();

    const std::span<const std::byte> bytes   = cst.getStruct();
    const uint32_t                   tagSize = tagged.taggedTagSize(sema.ctx());
    if (bytes.size() < offset + tagSize || tagSize > sizeof(uint64_t))
        return ConstantRef::invalid();

    uint64_t bits = 0;
    std::memcpy(&bits, bytes.data() + offset, tagSize);
    return caseFromBits(sema, tagged, bits);
}

Result SemaTagged::makeCaseConstant(Sema& sema, ConstantRef& outCstRef, TypeRef unionTypeRef, ConstantRef tagCstRef, ConstantRef payloadCstRef)
{
    const SymbolStruct* tagged = unionOf(sema.ctx(), unionTypeRef);
    SWC_ASSERT(tagged != nullptr);

    SmallVector<ConstantHelpers::ConstantPayloadWrite, 2> writes;
    writes.push_back({.offset = 0, .typeRef = tagged->taggedTypeRef(), .valueRef = tagCstRef});

    if (payloadCstRef.isValid())
    {
        const SymbolVariable* member = tagged->taggedCaseMember(tagCstRef);
        SWC_ASSERT(member != nullptr);
        writes.push_back({.offset = tagged->taggedPayloadOffset(), .typeRef = member->typeRef(), .valueRef = payloadCstRef});
    }

    outCstRef = ConstantHelpers::materializeAggregateConstructionConstant(sema, unionTypeRef, writes.span());
    return Result::Continue;
}

SWC_END_NAMESPACE();
