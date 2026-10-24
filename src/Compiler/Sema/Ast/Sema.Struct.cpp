#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaDeclGhost.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Helpers/SemaTagged.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    template<typename T>
    Result semaPreNodeStructCommon(Sema& sema, const T& node)
    {
        if (sema.enteringState())
            SemaHelpers::declareSymbol(sema, node);

        auto& sym = sema.curViewSymbol().sym()->cast<SymbolStruct>();
        if (!sym.isGenericInstance())
            SWC_RESULT(Match::ghosting(sema, sym));

        if (sym.isGenericRoot() && !sym.isGenericInstance())
        {
            if (!sym.isTyped())
                SemaHelpers::ensureStructTypeRef(sema, sym);

            sema.curViewSymbol().sym()->setSemaCompleted(sema.ctx());
            return Result::SkipChildren;
        }

        return Result::Continue;
    }

    Result checkDynamicFieldLayout(Sema& sema, const SymbolStruct& sym)
    {
        if (!sym.hasDynamicStorage())
            return Result::Continue;

        for (const SymbolVariable* field : sym.fields())
        {
            const TypeInfo& fieldType = sema.typeMgr().get(field->typeRef());
            if (!SymbolStruct::typeHasDynamicStorage(sema.ctx(), fieldType))
                continue;

            const uint64_t start = field->offset();
            const uint64_t end   = start + fieldType.sizeOf(sema.ctx());
            for (const SymbolVariable* other : sym.fields())
            {
                if (other == field)
                    continue;

                const uint64_t otherStart = other->offset();
                const uint64_t otherEnd   = otherStart + other->typeInfo(sema.ctx()).sizeOf(sema.ctx());
                if (start < otherEnd && otherStart < end)
                    return SemaError::raise(sema, DiagnosticId::sema_err_dynamic_layout, *field);
            }
        }

        return Result::Continue;
    }

    Result layoutAggregateFields(Sema& sema, SymbolStruct& sym)
    {
        sym.removeIgnoredFields();
        SWC_RESULT(sym.canBeCompleted(sema));
        SWC_RESULT(sym.computeLayout(sema.ctx()));
        return checkDynamicFieldLayout(sema, sym);
    }

    void bindSpecializedStructInitializerTarget(Sema& sema, AstNodeRef nodeWhatRef, SymbolStruct& instance, TypeRef specializedTypeRef)
    {
        sema.setSymbol(nodeWhatRef, &instance);
        if (specializedTypeRef.isValid())
            sema.setType(nodeWhatRef, specializedTypeRef);

        const auto* namedType = sema.node(nodeWhatRef).safeCast<AstNamedType>();
        if (!namedType)
            return;

        sema.setSymbol(namedType->nodeIdentRef, &instance);
        if (specializedTypeRef.isValid())
            sema.setType(namedType->nodeIdentRef, specializedTypeRef);
    }

    Result specializeGenericStructInitializerTarget(Sema& sema, AstNodeRef nodeWhatRef)
    {
        const SemaNodeView nodeWhatView = sema.viewSymbol(nodeWhatRef);
        if (!nodeWhatView.sym() || !nodeWhatView.sym()->isStruct())
            return Result::Continue;

        auto& st = nodeWhatView.sym()->cast<SymbolStruct>();
        if (!st.isGenericRoot() || st.isGenericInstance())
            return Result::Continue;

        SymbolStruct* instance = nullptr;
        SWC_RESULT(SemaGeneric::instantiateStructFromContext(sema, st, instance));
        if (!instance)
            return Result::Continue;

        const TypeRef specializedTypeRef = SemaHelpers::ensureStructTypeRef(sema, *instance);
        bindSpecializedStructInitializerTarget(sema, nodeWhatRef, *instance, specializedTypeRef);

        return Result::Continue;
    }

    Result semaPreNodeChildStructCommon(Sema& sema, AstNodeRef childRef, AstNodeRef nodeBodyRef)
    {
        if (childRef == nodeBodyRef)
        {
            TaskContext& ctx = sema.ctx();

            auto&          sym           = sema.curViewSymbol().sym()->cast<SymbolStruct>();
            const TypeInfo structType    = TypeInfo::makeStruct(&sym);
            const TypeRef  structTypeRef = ctx.typeMgr().addType(structType);

            sym.setTypeRef(structTypeRef);
            sym.setTyped(ctx);

            sema.pushScopePopOnPostNode(SemaScopeFlagsE::Type);
            sema.curScope().setSymMap(&sym);
        }

        return Result::Continue;
    }

    // 'union(Kind)': once the tag type is resolved, the union is tagged before its body declares
    // any member, so the 'case' labels can resolve their values against it.
    Result resolveTaggedUnionTag(Sema& sema, AstNodeRef tagTypeRef, AstNodeRef childRef, AstNodeRef bodyRef)
    {
        if (childRef != bodyRef || tagTypeRef.isInvalid())
            return Result::Continue;

        const TypeRef   declaredTagRef = sema.viewType(tagTypeRef).typeRef();
        const TypeInfo& tagType        = sema.typeMgr().get(declaredTagRef).unwrapAliasTypeOrSelf(sema.ctx());
        if (!tagType.isEnum())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_tagged_union_tag_not_enum, tagTypeRef);
            diag.addArgument(Diagnostic::ARG_TYPE, declaredTagRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        SWC_RESULT(sema.waitSemaCompleted(&tagType, tagTypeRef));
        if (tagType.isEnumFlags())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_tagged_union_tag_flags, tagTypeRef);
            diag.addArgument(Diagnostic::ARG_TYPE, declaredTagRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!sema.typeMgr().get(tagType.payloadSymEnum().underlyingTypeRef()).isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_tagged_union_tag_not_integer, tagTypeRef);
            diag.addArgument(Diagnostic::ARG_TYPE, declaredTagRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        auto& sym = sema.curViewSymbol().sym()->cast<SymbolStruct>();
        sym.setTaggedTypeRef(tagType.typeRef());
        return Result::Continue;
    }

    // Every member of a tagged union is selected by at least one tag value.
    Result checkTaggedUnionMembers(Sema& sema, const SymbolStruct& sym)
    {
        if (!sym.isTagged())
            return Result::Continue;

        for (const SymbolVariable* field : sym.fields())
        {
            if (!field || !sym.taggedCaseValues(*field).empty())
                continue;

            auto diag = SemaError::report(sema, DiagnosticId::sema_err_tagged_member_without_case, *field);
            diag.addArgument(Diagnostic::ARG_SYM, field->name(sema.ctx()));
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Continue;
    }

    SymbolStruct* currentTaggedUnion(Sema& sema)
    {
        SymbolMap* symMap = sema.curScope().symMap();
        if (!symMap || !symMap->isStruct())
            return nullptr;

        auto& sym = symMap->cast<SymbolStruct>();
        return sym.isTagged() ? &sym : nullptr;
    }

    // Replaces the current node with a tagged union literal of 'caseRef'. The payload, when there is
    // one, is a node the literal owns; nothing the current node already analyzed is reused.
    Result restartAsTaggedUnionLiteral(Sema& sema, TypeRef unionTypeRef, ConstantRef caseRef, AstNodeRef payloadRef)
    {
        const AstNode& node            = sema.curNode();
        auto [literalRef, literalNode] = sema.ast().makeNode<AstNodeId::TaggedUnionLiteral>(node.tokRef());
        literalNode->setCodeRef(node.codeRef());
        literalNode->unionTypeRef   = unionTypeRef;
        literalNode->tagCstRef      = caseRef;
        literalNode->nodePayloadRef = payloadRef;

        sema.setSubstitute(sema.curNodeRef(), literalRef);
        sema.restartCurrentNode(literalRef);
        return Result::Continue;
    }

    Result pushStructInitializerChildBindingType(Sema& sema, AstNodeRef childRef, TypeRef targetTypeRef, SpanRef spanArgsRef)
    {
        SmallVector<AstNodeRef> children;
        AstNode::collectChildren(children, sema.ast(), spanArgsRef);

        TypeRef bindingTypeRef = TypeRef::invalid();
        SWC_RESULT(SemaHelpers::resolveStructLikeChildBindingType(sema, children.span(), childRef, targetTypeRef, bindingTypeRef));
        if (!bindingTypeRef.isValid())
            return Result::Continue;

        auto frame = sema.frame();
        frame.pushBindingType(bindingTypeRef);
        sema.pushFramePopOnPostChild(std::move(frame), childRef);

        return Result::Continue;
    }
}

Result AstStructDecl::semaPreDecl(Sema& sema) const
{
    auto& sym = SemaHelpers::registerSymbol<SymbolStruct>(sema, *this, tokNameRef);
    sym.setDeclNodeRef(sema.curNodeRef());
    sym.setGenericRoot(spanGenericParamsRef.isValid());

    if (sym.inSwagNamespace(sema.ctx()) && sema.typeMgr().isTypeInfoRuntimeStruct(sym.idRef()))
        sym.addExtraFlag(SymbolStructFlagsE::TypeInfo);

    return Result::SkipChildren;
}

Result AstStructDecl::semaPreNode(Sema& sema) const
{
    return semaPreNodeStructCommon(sema, *this);
}

Result AstStructDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    return semaPreNodeChildStructCommon(sema, childRef, nodeBodyRef);
}

Result AstStructDecl::semaPostNode(Sema& sema)
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolStruct>();
    if (sym.isGenericRoot() && !sym.isGenericInstance())
    {
        if (sema.compiler().pendingImplRegistrations(sym.idRef()) != 0)
            return sema.waitImplRegistrations(sym.idRef(), sym.codeRef());

        return SemaSpecOp::ensureGeneratedOperators(sema, sym);
    }

    SWC_RESULT(layoutAggregateFields(sema, sym));

    // Ensure all `impl` blocks (including interface implementations) have been registered
    // before a struct can be marked as completed.
    if (sema.compiler().pendingImplRegistrations(sym.idRef()) != 0)
        return sema.waitImplRegistrations(sym.idRef(), sym.codeRef());

    if (!sym.isGenericInstance())
        SWC_RESULT(SemaSpecOp::ensureGeneratedLifecycleFunctions(sema, sym));

    SWC_RESULT(SemaSpecOp::ensureGeneratedOperators(sema, sym));
    SWC_RESULT(SemaSpecOp::ensureGeneratedEquality(sema, sym));
    SWC_RESULT(sym.registerSpecOps(sema));

    if (sym.inSwagNamespace(sema.ctx()))
        sema.typeMgr().registerRuntimeType(sym.idRef(), sym.typeRef());

    if (sym.isGenericInstance())
        return Result::Continue;

    sym.setSemaCompleted(sema.ctx());

    return Result::Continue;
}

Result AstUnionDecl::semaPreDecl(Sema& sema) const
{
    auto& sym = SemaHelpers::registerSymbol<SymbolStruct>(sema, *this, tokNameRef);
    sym.setDeclNodeRef(sema.curNodeRef());
    sym.setGenericRoot(spanGenericParamsRef.isValid());
    sym.addExtraFlag(SymbolStructFlagsE::Union);
    if (nodeTagTypeRef.isValid())
        sym.addExtraFlag(SymbolStructFlagsE::Tagged);

    return Result::SkipChildren;
}

Result AstUnionDecl::semaPreNode(Sema& sema) const
{
    return semaPreNodeStructCommon(sema, *this);
}

Result AstUnionDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    SWC_RESULT(resolveTaggedUnionTag(sema, nodeTagTypeRef, childRef, nodeBodyRef));
    return semaPreNodeChildStructCommon(sema, childRef, nodeBodyRef);
}

Result AstUnionDecl::semaPostNode(Sema& sema)
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolStruct>();
    if (sym.isGenericRoot() && !sym.isGenericInstance())
        return Result::Continue;

    SWC_RESULT(checkTaggedUnionMembers(sema, sym));
    SWC_RESULT(layoutAggregateFields(sema, sym));

    if (sema.compiler().pendingImplRegistrations(sym.idRef()) != 0)
        return sema.waitImplRegistrations(sym.idRef(), sym.codeRef());

    if (!sym.isGenericInstance())
        SWC_RESULT(SemaSpecOp::ensureGeneratedLifecycleFunctions(sema, sym));

    if (sym.isTagged())
        SWC_RESULT(SemaSpecOp::ensureGeneratedEquality(sema, sym));

    SWC_RESULT(sym.registerSpecOps(sema));

    if (sym.isGenericInstance())
        return Result::Continue;

    sym.setSemaCompleted(sema.ctx());

    return Result::Continue;
}

Result AstAnonymousStructDecl::semaPreDecl(Sema& sema) const
{
    auto& sym = SemaHelpers::registerUniqueSymbol<SymbolStruct>(sema, *this, "anonymous_struct");
    sym.addExtraFlag(SymbolStructFlagsE::Anonymous);

    return Result::SkipChildren;
}

Result AstAnonymousStructDecl::semaPreNode(Sema& sema) const
{
    return SemaDeclGhost::run(sema, *this);
}

Result AstAnonymousStructDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    return semaPreNodeChildStructCommon(sema, childRef, nodeBodyRef);
}

Result AstAnonymousStructDecl::semaPostNode(Sema& sema)
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolStruct>();

    SWC_RESULT(layoutAggregateFields(sema, sym));

    // Ensure all `impl` blocks (including interface implementations) have been registered
    // before a struct can be marked as completed.
    if (sema.compiler().pendingImplRegistrations(sym.idRef()) != 0)
        return sema.waitImplRegistrations(sym.idRef(), sym.codeRef());

    sym.setSemaCompleted(sema.ctx());

    // Keep the declaration symbol: a lazy body can revisit its signature, and
    // its fields still belong to this aggregate. The symbol also exposes its type.
    return Result::Continue;
}

Result AstAnonymousUnionDecl::semaPreDecl(Sema& sema) const
{
    auto& sym = SemaHelpers::registerUniqueSymbol<SymbolStruct>(sema, *this, "anonymous_union");
    sym.addExtraFlag(SymbolStructFlagsE::Union);
    sym.addExtraFlag(SymbolStructFlagsE::Anonymous);
    if (nodeTagTypeRef.isValid())
        sym.addExtraFlag(SymbolStructFlagsE::Tagged);

    return Result::SkipChildren;
}

Result AstAnonymousUnionDecl::semaPreNode(Sema& sema) const
{
    return SemaDeclGhost::run(sema, *this);
}

Result AstAnonymousUnionDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    SWC_RESULT(resolveTaggedUnionTag(sema, nodeTagTypeRef, childRef, nodeBodyRef));
    return semaPreNodeChildStructCommon(sema, childRef, nodeBodyRef);
}

Result AstAnonymousUnionDecl::semaPostNode(Sema& sema)
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolStruct>();
    SWC_RESULT(checkTaggedUnionMembers(sema, sym));
    SWC_RESULT(layoutAggregateFields(sema, sym));

    // The holder compares this member with '==', so a tagged union needs its own answer: a byte
    // comparison is only right when every case compares as bytes.
    if (sym.isTagged())
        SWC_RESULT(SemaSpecOp::ensureGeneratedEquality(sema, sym));

    sym.setSemaCompleted(sema.ctx());

    // As with anonymous structs, replay must reuse the owner of the field symbols.
    return Result::Continue;
}

Result AstTaggedUnionCase::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    const SymbolStruct* tagged = currentTaggedUnion(sema);
    if (!tagged)
        return SemaError::raise(sema, DiagnosticId::sema_err_tagged_case_outside_tagged_union, sema.curNodeRef());

    if (childRef == nodeMemberRef)
        return Result::Continue;

    // A label value is a tag value: '.Circle' names a value of the tag before anything else.
    auto frame = sema.frame();
    frame.pushBindingType(tagged->taggedTypeRef());
    sema.pushFramePopOnPostChild(std::move(frame), childRef);
    SemaHelpers::preferContextualAutoMemberBindingType(sema, childRef);
    return Result::Continue;
}

Result AstTaggedUnionCase::semaPostNode(Sema& sema) const
{
    SymbolStruct* tagged = currentTaggedUnion(sema);
    SWC_ASSERT(tagged != nullptr);

    if (sema.node(nodeMemberRef).isNot(AstNodeId::SingleVarDecl))
        return SemaError::raise(sema, DiagnosticId::sema_err_tagged_case_one_member, nodeMemberRef);

    const Symbol* memberSym = sema.viewSymbol(nodeMemberRef).sym();
    if (!memberSym || !memberSym->isVariable())
        return Result::Error;

    const auto& member = memberSym->cast<SymbolVariable>();

    SmallVector<ConstantRef> values;
    SmallVector<AstNodeRef>  valueRefs;
    AstNode::collectChildren(valueRefs, sema.ast(), spanValuesRef);
    for (const AstNodeRef valueRef : valueRefs)
    {
        SemaNodeView view = sema.viewNodeTypeConstant(valueRef);
        SWC_RESULT(Cast::cast(sema, view, tagged->taggedTypeRef(), CastKind::Implicit));

        const SemaNodeView cstView = sema.viewConstant(valueRef);
        if (!cstView.hasConstant())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_tagged_case_not_const, valueRef);
            diag.addArgument(Diagnostic::ARG_TYPE, tagged->taggedTypeRef());
            diag.report(sema.ctx());
            return Result::Error;
        }

        const ConstantRef     value    = cstView.cstRef();
        const SymbolVariable* previous = tagged->taggedCaseMember(value);
        if ((previous && previous != &member) || std::ranges::find(values, value) != values.end())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_tagged_case_duplicate, valueRef);
            diag.addArgument(Diagnostic::ARG_VALUE, SemaTagged::caseName(sema, *tagged, value));
            diag.report(sema.ctx());
            return Result::Error;
        }

        values.push_back(value);
    }

    tagged->addTaggedCase(member, SemaTagged::copyCases(sema, values.span()));
    return Result::Continue;
}

// '.Circle{radius: 2}' in a slot expecting a tagged union: the braces build the payload of that
// case. Rewritten before anything below is analyzed, so the arguments see the payload type.
Result AstStructInitializerList::semaPreNode(Sema& sema) const
{
    if (sema.node(nodeWhatRef).isNot(AstNodeId::AutoMemberAccessExpr))
        return Result::Continue;

    TypeRef             unionTypeRef = TypeRef::invalid();
    const SymbolStruct* tagged       = nullptr;
    SWC_RESULT(SemaTagged::contextUnion(sema, tagged, unionTypeRef));
    if (!tagged)
        return Result::Continue;

    const auto&         caseNode = sema.node(nodeWhatRef).cast<AstAutoMemberAccessExpr>();
    const IdentifierRef idRef    = SemaHelpers::resolveIdentifier(sema, sema.node(caseNode.nodeIdentRef).codeRef());
    ConstantRef         caseRef  = ConstantRef::invalid();
    SWC_RESULT(SemaTagged::findCase(sema, caseRef, *tagged, idRef));
    if (caseRef.isInvalid())
        return Result::Continue;

    const SymbolVariable* member = tagged->taggedCaseMember(caseRef);
    if (!member)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_tagged_case_no_payload, sema.curNodeRef());
        diag.addArgument(Diagnostic::ARG_VALUE, SemaTagged::caseName(sema, *tagged, caseRef));
        diag.report(sema.ctx());
        return Result::Error;
    }

    // A struct or array payload takes the braces as its own initializer list; any other payload
    // is the single value they hold.
    AstNodeRef      payloadRef  = AstNodeRef::invalid();
    const TypeInfo& payloadType = sema.typeMgr().get(member->typeRef()).unwrapAliasTypeOrSelf(sema.ctx());
    if (payloadType.isStructOrArray())
    {
        const AstNode& identNode    = sema.node(caseNode.nodeIdentRef);
        auto [typeRef, typeNode]    = sema.ast().makeNode<AstNodeId::Identifier>(identNode.tokRef());
        auto [payloadInitRef, init] = sema.ast().makeNode<AstNodeId::StructInitializerList>(tokRef());
        typeNode->setCodeRef(identNode.codeRef());
        typeNode->addFlag(AstIdentifierFlagsE::GenericTypeBinding);
        sema.setType(typeRef, member->typeRef());
        init->setCodeRef(codeRef());
        init->nodeWhatRef = typeRef;
        init->spanArgsRef = spanArgsRef;
        payloadRef        = payloadInitRef;
    }
    else
    {
        SmallVector<AstNodeRef> args;
        AstNode::collectChildren(args, sema.ast(), spanArgsRef);
        if (args.size() != 1)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_tagged_case_scalar_payload, sema.curNodeRef());
            diag.addArgument(Diagnostic::ARG_VALUE, SemaTagged::caseName(sema, *tagged, caseRef));
            diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(args.size()));
            diag.report(sema.ctx());
            return Result::Error;
        }

        payloadRef = args.front();
        if (const auto* named = sema.node(payloadRef).safeCast<AstNamedArgument>())
            payloadRef = named->nodeArgRef;
    }

    return restartAsTaggedUnionLiteral(sema, unionTypeRef, caseRef, payloadRef);
}

Result AstTaggedUnionLiteral::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    const SymbolStruct* tagged = SemaTagged::unionOf(sema.ctx(), unionTypeRef);
    SWC_ASSERT(tagged != nullptr);

    const SymbolVariable* member = tagged->taggedCaseMember(tagCstRef);
    SWC_ASSERT(member != nullptr);

    auto frame = sema.frame();
    frame.pushBindingType(member->typeRef());
    sema.pushFramePopOnPostChild(std::move(frame), childRef);
    return Result::Continue;
}

Result AstTaggedUnionLiteral::semaPostNode(Sema& sema) const
{
    const SymbolStruct* tagged = SemaTagged::unionOf(sema.ctx(), unionTypeRef);
    SWC_ASSERT(tagged != nullptr);

    const SymbolVariable* member        = tagged->taggedCaseMember(tagCstRef);
    ConstantRef           payloadCstRef = ConstantRef::invalid();

    if (nodePayloadRef.isValid())
    {
        SemaNodeView payloadView = sema.viewNodeTypeConstant(nodePayloadRef);
        SWC_RESULT(Cast::cast(sema, payloadView, member->typeRef(), CastKind::Initialization));

        const SemaNodeView castView = sema.viewNodeTypeConstant(nodePayloadRef);
        if (!castView.hasConstant())
        {
            sema.setType(sema.curNodeRef(), unionTypeRef);
            sema.setIsValue(sema.curNodeRef());
            return SemaHelpers::attachRuntimeStorageIfNeeded(sema, *this, unionTypeRef, "__tagged_literal_runtime_storage");
        }

        payloadCstRef = castView.cstRef();
    }
    else if (member)
    {
        // A case without braces takes the default its member declares, else its type's default.
        payloadCstRef = member->defaultValueRef();
        if (payloadCstRef.isInvalid())
        {
            if (SymbolStruct::fieldRequiresExplicitInitialization(sema, *member))
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_tagged_case_needs_payload, sema.curNodeRef());
                diag.addArgument(Diagnostic::ARG_VALUE, SemaTagged::caseName(sema, *tagged, tagCstRef));
                diag.addArgument(Diagnostic::ARG_SYM, member->name(sema.ctx()));
                diag.report(sema.ctx());
                return Result::Error;
            }

            if (sema.typeMgr().get(member->typeRef()).unwrapAliasTypeOrSelf(sema.ctx()).isStructOrArray())
                payloadCstRef = ConstantHelpers::materializeAggregateConstructionConstant(sema, member->typeRef());
        }
    }

    ConstantRef cstRef = ConstantRef::invalid();
    SWC_RESULT(SemaTagged::makeCaseConstant(sema, cstRef, unionTypeRef, tagCstRef, payloadCstRef));
    SWC_ASSERT(cstRef.isValid());
    if (cstRef.isInvalid())
        return Result::Error;

    sema.setConstant(sema.curNodeRef(), cstRef);
    return Result::Continue;
}

Result AstStructInitializerList::semaPostNode(Sema& sema) const
{
    SWC_RESULT(specializeGenericStructInitializerTarget(sema, nodeWhatRef));

    // Foo{...} requires a type. Reject untyped symbols here so initialization
    // cannot pass an invalid TypeRef to the cast below.
    if (sema.viewType(nodeWhatRef).typeRef().isInvalid())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_type, nodeWhatRef);

    // A tagged union value names its case; listing members would leave the tag unwritten.
    if (SemaTagged::unionOf(sema.ctx(), sema.viewType(nodeWhatRef).typeRef()))
        return SemaError::raise(sema, DiagnosticId::sema_err_tagged_union_literal, sema.curNodeRef());

    SmallVector<AstNodeRef> children;
    AstNode::collectChildren(children, sema.ast(), spanArgsRef);

    SWC_RESULT(SemaHelpers::finalizeAggregateStruct(sema, children));

    SemaNodeView initView = sema.curViewNodeTypeConstant();
    SWC_RESULT(SemaHelpers::attachLiteralRuntimeStorageIfNeeded(sema, *this, initView));

    SWC_RESULT(Cast::cast(sema, initView, sema.viewType(nodeWhatRef).typeRef(), CastKind::Initialization));

    return Result::Continue;
}

Result AstStructInitializerList::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeWhatRef)
        return Result::Continue;

    SWC_RESULT(specializeGenericStructInitializerTarget(sema, nodeWhatRef));

    const TypeRef targetTypeRef = sema.viewType(nodeWhatRef).typeRef();
    if (!targetTypeRef.isValid())
        return Result::Continue;

    return pushStructInitializerChildBindingType(sema, childRef, targetTypeRef, spanArgsRef);
}

SWC_END_NAMESPACE();
