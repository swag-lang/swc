#include "pch.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Memory/Heap.h"
#include "Support/Report/Assert.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef unwrapAlias(TaskContext& ctx, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return typeRef;
        return ctx.typeMgr().get(typeRef).unwrap(ctx, typeRef, TypeExpandE::Alias);
    }

    const SymbolFunction* findDeclaredLifecycleMethod(const TaskContext& ctx, const SymbolStruct& ownerStruct, const SpecOpKind kind)
    {
        const std::string_view expectedName = SemaSpecOp::specOpFunctionName(kind);
        for (const SymbolFunction* symFunc : ownerStruct.declaredMethods())
        {
            if (!symFunc || symFunc->attributes().hasRtFlag(RtAttributeFlagsE::Implicit))
                continue;
            if (const SymbolImpl* symImpl = symFunc->declImplContext(); symImpl && symImpl->isForInterface())
                continue;
            if (symFunc->specOpKind() == kind || symFunc->name(ctx) == expectedName)
                return symFunc;
        }

        return nullptr;
    }

    Result runGeneratedImplPass(TaskContext& ctx, Sema& sema, AstNodeRef generatedRoot, SymbolImpl& symImpl, const AttributeList& attributes, const bool declPass)
    {
        Sema generatedSema(ctx, sema, generatedRoot, declPass);
        SemaGeneric::prepareGenericInstantiationContext(generatedSema, symImpl.asSymMap(), &symImpl, nullptr, attributes);
        const Result result = generatedSema.execResult();
        SWC_ASSERT(result != Result::Pause);
        return result;
    }

    bool hasDirectLifecycle(const TaskContext& ctx, const SymbolStruct& ownerStruct, const SpecOpKind kind)
    {
        if (findDeclaredLifecycleMethod(ctx, ownerStruct, kind))
            return true;

        switch (kind)
        {
            case SpecOpKind::OpDrop:
                return ownerStruct.opDrop() != nullptr;
            case SpecOpKind::OpPostCopy:
                return ownerStruct.opPostCopy() != nullptr;
            case SpecOpKind::OpPostMove:
                return ownerStruct.opPostMove() != nullptr;
            default:
                return false;
        }
    }

    bool typeHasLifecycleRec(TaskContext& ctx, TypeRef typeRef, const SpecOpKind kind, std::unordered_set<TypeRef>& visiting)
    {
        typeRef = unwrapAlias(ctx, typeRef);
        if (typeRef.isInvalid())
            return false;

        if (!visiting.insert(typeRef).second)
            return false;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (type.isVoid() || type.isNull() || type.isUndefined())
        {
            visiting.erase(typeRef);
            return false;
        }

        if (type.isArray())
        {
            uint64_t totalCount = 1;
            for (const uint64_t dim : type.payloadArrayDims())
                totalCount *= dim;
            const bool result = totalCount && typeHasLifecycleRec(ctx, type.payloadArrayElemTypeRef(), kind, visiting);
            visiting.erase(typeRef);
            return result;
        }

        if (type.isAggregateStruct() || type.isAggregateArray())
        {
            for (const TypeRef fieldTypeRef : type.payloadAggregate().types)
            {
                if (typeHasLifecycleRec(ctx, fieldTypeRef, kind, visiting))
                {
                    visiting.erase(typeRef);
                    return true;
                }
            }

            visiting.erase(typeRef);
            return false;
        }

        if (!type.isStruct())
        {
            visiting.erase(typeRef);
            return false;
        }

        const SymbolStruct& ownerStruct = type.payloadSymStruct();
        if (hasDirectLifecycle(ctx, ownerStruct, kind))
        {
            visiting.erase(typeRef);
            return true;
        }

        for (const SymbolVariable* field : ownerStruct.fields())
        {
            if (field && typeHasLifecycleRec(ctx, field->typeRef(), kind, visiting))
            {
                visiting.erase(typeRef);
                return true;
            }
        }

        visiting.erase(typeRef);
        return false;
    }

    SourceCodeRef operatorGenerationErrorCodeRef(const SymbolStruct& ownerStruct)
    {
        const AttributeList& attributes = ownerStruct.attributes();
        if (attributes.generatedOperatorsCodeRef.isValid())
            return attributes.generatedOperatorsCodeRef;
        return ownerStruct.codeRef();
    }

    std::string_view predefinedName(Sema& sema, IdentifierManager::PredefinedName name)
    {
        return sema.idMgr().get(sema.idMgr().predefined(name)).name;
    }

    IdentifierRef specOpIdFromKind(Sema& sema, SpecOpKind kind)
    {
        switch (kind)
        {
            case SpecOpKind::OpEquals:
                return sema.idMgr().predefined(IdentifierManager::PredefinedName::OpEquals);
            case SpecOpKind::OpCompare:
                return sema.idMgr().predefined(IdentifierManager::PredefinedName::OpCompare);
            default:
                return IdentifierRef::invalid();
        }
    }

    const SymbolFunction* findDeclaredOperatorOverload(Sema& sema, const SymbolStruct& ownerStruct, SpecOpKind kind)
    {
        const IdentifierRef idRef = specOpIdFromKind(sema, kind);
        if (!idRef.isValid())
            return nullptr;

        for (const SymbolImpl* impl : ownerStruct.impls())
        {
            if (!impl)
                continue;

            for (const SymbolFunction* function : impl->specOps())
            {
                if (function && function->idRef() == idRef)
                    return function;
            }
        }

        return nullptr;
    }

    GeneratedOperatorFlags generatedOperatorFlagFromKind(SpecOpKind kind)
    {
        switch (kind)
        {
            case SpecOpKind::OpEquals:
                return GeneratedOperatorFlagsE::OpEquals;
            case SpecOpKind::OpCompare:
                return GeneratedOperatorFlagsE::OpCompare;
            default:
                return GeneratedOperatorFlagsE::Zero;
        }
    }

    TypeRef generatedOperatorFieldTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& fieldType = sema.typeMgr().get(typeRef);
        if (fieldType.isReference())
            typeRef = fieldType.payloadTypeRef();

        const TypeRef unwrappedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        return unwrappedTypeRef.isValid() ? unwrappedTypeRef : typeRef;
    }

    const SymbolStruct* generatedOperatorFieldStruct(Sema& sema, TypeRef typeRef)
    {
        typeRef = generatedOperatorFieldTypeRef(sema, typeRef);
        if (!typeRef.isValid())
            return nullptr;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (!type.isStruct())
            return nullptr;

        return &type.payloadSymStruct();
    }

    bool structSupportsGeneratedOperator(Sema& sema, const SymbolStruct& ownerStruct, SpecOpKind kind)
    {
        if (findDeclaredOperatorOverload(sema, ownerStruct, kind))
            return true;

        const GeneratedOperatorFlags flag = generatedOperatorFlagFromKind(kind);
        return flag.any() && ownerStruct.attributes().generatedOperators.has(flag);
    }

    bool builtinTypeSupportsGeneratedOperator(Sema& sema, TypeRef typeRef, SpecOpKind kind)
    {
        typeRef = generatedOperatorFieldTypeRef(sema, typeRef);
        if (!typeRef.isValid())
            return false;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        switch (kind)
        {
            case SpecOpKind::OpEquals:
                return type.isBool() || type.isScalarNumeric() || type.isPointerLike();
            case SpecOpKind::OpCompare:
                return type.isScalarNumeric() || type.isAnyPointer();
            default:
                return false;
        }
    }

    bool fieldSupportsGeneratedOperator(Sema& sema, const SymbolVariable& field, SpecOpKind kind)
    {
        if (const SymbolStruct* fieldStruct = generatedOperatorFieldStruct(sema, field.typeRef()))
            return structSupportsGeneratedOperator(sema, *fieldStruct, kind);

        return builtinTypeSupportsGeneratedOperator(sema, field.typeRef(), kind);
    }

    bool isGeneratedOperatorField(const SymbolVariable& field)
    {
        return !field.isIgnored() && !field.attributes().hasRtFlag(RtAttributeFlagsE::OperatorIgnore);
    }

    Result reportGeneratedOperatorUnsupportedField(Sema& sema, const SymbolStruct& ownerStruct, const SymbolVariable& field, SpecOpKind kind)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_operator_generation_field_unsupported, field);
        diag.addArgument(Diagnostic::ARG_SPEC_OP, SemaSpecOp::specOpFunctionName(kind));
        diag.addArgument(Diagnostic::ARG_DECL_SYM, ownerStruct.name(sema.ctx()));
        diag.addArgument(Diagnostic::ARG_SYM, field.name(sema.ctx()));

        if (const SymbolStruct* fieldStruct = generatedOperatorFieldStruct(sema, field.typeRef()))
            SemaSpecOp::addMissingDeclarationHelp(sema, diag, *fieldStruct, kind);

        diag.report(sema.ctx());
        return Result::Error;
    }

    Result validateGeneratedOperatorFieldSupport(Sema& sema, const SymbolStruct& ownerStruct, GeneratedOperatorFlags flags)
    {
        for (const SymbolVariable* field : ownerStruct.fields())
        {
            if (!field || !isGeneratedOperatorField(*field))
                continue;

            if (flags.has(GeneratedOperatorFlagsE::OpEquals) && !fieldSupportsGeneratedOperator(sema, *field, SpecOpKind::OpEquals))
                return reportGeneratedOperatorUnsupportedField(sema, ownerStruct, *field, SpecOpKind::OpEquals);

            if (flags.has(GeneratedOperatorFlagsE::OpCompare) && !fieldSupportsGeneratedOperator(sema, *field, SpecOpKind::OpCompare))
                return reportGeneratedOperatorUnsupportedField(sema, ownerStruct, *field, SpecOpKind::OpCompare);
        }

        return Result::Continue;
    }

    Result reportGeneratedOperatorDuplicate(Sema& sema, const SymbolStruct& ownerStruct, SpecOpKind kind, const SymbolFunction& existing)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_operator_generation_duplicate, operatorGenerationErrorCodeRef(ownerStruct));
        diag.addArgument(Diagnostic::ARG_SPEC_OP, SemaSpecOp::specOpFunctionName(kind));
        diag.addArgument(Diagnostic::ARG_DECL_SYM, ownerStruct.name(sema.ctx()));
        diag.addNote(DiagnosticId::sema_note_other_definition);
        diag.last().addSpan(existing.codeRange(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result validateGeneratedOperatorDuplicates(Sema& sema, const SymbolStruct& ownerStruct, GeneratedOperatorFlags flags)
    {
        if (flags.has(GeneratedOperatorFlagsE::OpEquals))
        {
            if (const SymbolFunction* existing = findDeclaredOperatorOverload(sema, ownerStruct, SpecOpKind::OpEquals))
                return reportGeneratedOperatorDuplicate(sema, ownerStruct, SpecOpKind::OpEquals, *existing);
        }

        if (flags.has(GeneratedOperatorFlagsE::OpCompare))
        {
            if (const SymbolFunction* existing = findDeclaredOperatorOverload(sema, ownerStruct, SpecOpKind::OpCompare))
                return reportGeneratedOperatorDuplicate(sema, ownerStruct, SpecOpKind::OpCompare, *existing);
        }

        return Result::Continue;
    }

    void collectGeneratedOperatorFieldNamesFromSymbols(const TaskContext& ctx, const SymbolStruct& ownerStruct, SmallVector<Utf8>& outFields)
    {
        for (const SymbolVariable* field : ownerStruct.fields())
        {
            if (!field || !isGeneratedOperatorField(*field))
                continue;
            outFields.push_back(field->name(ctx));
        }
    }

    bool generatedOperatorAttributeMatches(Sema& sema, AstNodeRef nodeRef, IdentifierManager::PredefinedName attributeName)
    {
        if (nodeRef.isInvalid())
            return false;

        const AstNode& node = sema.node(nodeRef);
        if (node.is(AstNodeId::Identifier))
            return sema.idMgr().addIdentifier(sema.ctx(), node.codeRef()) == sema.idMgr().predefined(attributeName);

        if (const auto* memberAccess = node.safeCast<AstMemberAccessExpr>())
            return generatedOperatorAttributeMatches(sema, memberAccess->nodeRightRef, attributeName);

        if (const auto* call = node.safeCast<AstCallExpr>())
            return generatedOperatorAttributeMatches(sema, call->nodeExprRef, attributeName);

        return false;
    }

    bool hasOperatorIgnoreAttribute(Sema& sema, const AstAttributeList& attrList)
    {
        SmallVector<AstNodeRef> attributes;
        sema.ast().appendNodes(attributes, attrList.spanChildrenRef);
        for (const AstNodeRef attrRef : attributes)
        {
            const AstNode& attrNode = sema.node(attrRef);
            const auto*    attr     = attrNode.safeCast<AstAttribute>();
            if (attr && generatedOperatorAttributeMatches(sema, attr->nodeCallRef, IdentifierManager::PredefinedName::OperatorIgnore))
                return true;
        }

        return false;
    }

    void collectGeneratedOperatorFieldNamesFromNode(Sema& sema, AstNodeRef nodeRef, SmallVector<Utf8>& outFields)
    {
        if (nodeRef.isInvalid())
            return;

        const AstNode& node = sema.node(nodeRef);
        if (const auto* attrList = node.safeCast<AstAttributeList>())
        {
            if (hasOperatorIgnoreAttribute(sema, *attrList))
                return;
            collectGeneratedOperatorFieldNamesFromNode(sema, attrList->nodeBodyRef, outFields);
            return;
        }

        if (const auto* access = node.safeCast<AstAccessModifier>())
        {
            collectGeneratedOperatorFieldNamesFromNode(sema, access->nodeWhatRef, outFields);
            return;
        }

        if (const auto* singleVar = node.safeCast<AstSingleVarDecl>())
        {
            if (!singleVar->hasFlag(AstVarDeclFlagsE::Const))
                outFields.push_back(Utf8{sema.tokenString({singleVar->srcViewRef(), singleVar->tokNameRef})});
            return;
        }

        if (const auto* multiVar = node.safeCast<AstMultiVarDecl>())
        {
            if (multiVar->hasFlag(AstVarDeclFlagsE::Const))
                return;

            SmallVector<TokenRef> names;
            sema.ast().appendTokens(names, multiVar->spanNamesRef);
            for (const TokenRef nameRef : names)
                outFields.push_back(Utf8{sema.tokenString({multiVar->srcViewRef(), nameRef})});
        }
    }

    void collectGeneratedOperatorFieldNamesFromAst(Sema& sema, const SymbolStruct& ownerStruct, SmallVector<Utf8>& outFields)
    {
        const AstNode* decl = ownerStruct.decl();
        const auto*    node = decl ? decl->safeCast<AstStructDecl>() : nullptr;
        if (!node || node->nodeBodyRef.isInvalid())
            return;

        SmallVector<AstNodeRef> children;
        sema.node(node->nodeBodyRef).collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
            collectGeneratedOperatorFieldNamesFromNode(sema, childRef, outFields);
    }

    void collectGeneratedOperatorFieldNames(Sema& sema, const SymbolStruct& ownerStruct, SmallVector<Utf8>& outFields)
    {
        outFields.clear();
        if (ownerStruct.isGenericRoot() && !ownerStruct.isGenericInstance())
            collectGeneratedOperatorFieldNamesFromAst(sema, ownerStruct, outFields);
        else
            collectGeneratedOperatorFieldNamesFromSymbols(sema.ctx(), ownerStruct, outFields);
    }

    void appendGeneratedAccess(Utf8& source, const SymbolStruct& ownerStruct)
    {
        source += "    ";
        if (ownerStruct.isPublic())
            source += "public ";
    }

    void appendGeneratedCompareOperator(Sema& sema, Utf8& source, const SymbolStruct& ownerStruct, std::span<const Utf8> fields)
    {
        appendGeneratedAccess(source, ownerStruct);
        source += "mtd const ";
        source += predefinedName(sema, IdentifierManager::PredefinedName::OpCompare);
        source += "(other: const &";
        source += ownerStruct.name(sema.ctx());
        source += ")->s32\n";
        source += "    {\n";
        for (size_t i = 0; i < fields.size(); ++i)
        {
            const Utf8 tempName = Utf8("swagCmp") + std::to_string(i);
            source += "        let ";
            source += tempName;
            source += " = .";
            source += fields[i];
            source += " <=> other.";
            source += fields[i];
            source += "\n";
            source += "        if ";
            source += tempName;
            source += " != 0 do return ";
            source += tempName;
            source += "\n";
        }

        source += "        return 0\n";
        source += "    }\n";
    }

    void appendGeneratedEqualsFieldComparison(Utf8& source, std::span<const Utf8> fields)
    {
        if (fields.empty())
        {
            source += "        return true\n";
            return;
        }

        source += "        return ";
        for (size_t i = 0; i < fields.size(); ++i)
        {
            if (i != 0)
                source += " and ";
            source += ".";
            source += fields[i];
            source += " == other.";
            source += fields[i];
        }
        source += "\n";
    }

    void appendGeneratedEqualsOperator(Sema& sema, Utf8& source, const SymbolStruct& ownerStruct, std::span<const Utf8> fields)
    {
        appendGeneratedAccess(source, ownerStruct);
        source += "mtd const ";
        source += predefinedName(sema, IdentifierManager::PredefinedName::OpEquals);
        source += "(other: const &";
        source += ownerStruct.name(sema.ctx());
        source += ")->bool\n";
        source += "    {\n";
        appendGeneratedEqualsFieldComparison(source, fields);
        source += "    }\n";
    }

    Utf8 makeGeneratedOperatorsSource(Sema& sema, const SymbolStruct& ownerStruct, GeneratedOperatorFlags flags)
    {
        SmallVector<Utf8> fields;
        collectGeneratedOperatorFieldNames(sema, ownerStruct, fields);
        const Utf8 ownerTypeName = ownerStruct.typeInfo(sema.ctx()).toName(sema.ctx());

        Utf8 source;
        source += "// Generated by #[Swag.Operators].\n";
        source += "impl ";
        source += ownerTypeName;
        source += "\n{\n";

        const bool generateCompare = flags.has(GeneratedOperatorFlagsE::OpCompare);
        if (generateCompare)
        {
            appendGeneratedCompareOperator(sema, source, ownerStruct, fields.span());
            if (flags.has(GeneratedOperatorFlagsE::OpEquals))
                source += "\n";
        }

        if (flags.has(GeneratedOperatorFlagsE::OpEquals))
            appendGeneratedEqualsOperator(sema, source, ownerStruct, fields.span());

        source += "}\n";
        return source;
    }

    bool hasGeneratedLifecycleWrapper(const TaskContext& ctx, const SymbolStruct& ownerStruct)
    {
        for (const SymbolFunction* symFunc : ownerStruct.declaredMethods())
        {
            if (!symFunc || !symFunc->attributes().hasRtFlag(RtAttributeFlagsE::Implicit))
                continue;

            const std::string_view name = symFunc->name(ctx);
            if (SemaSpecOp::isGeneratedLifecycleWrapperName(name))
                return true;
        }

        return false;
    }

    std::string_view lifecycleIntrinsicName(const SpecOpKind kind)
    {
        switch (kind)
        {
            case SpecOpKind::OpDrop:
                return "@drop";
            case SpecOpKind::OpPostCopy:
                return "@postcopy";
            case SpecOpKind::OpPostMove:
                return "@postmove";
            default:
                return {};
        }
    }

    bool shouldGenerateLifecycleWrapper(Sema& sema, const SymbolStruct& ownerStruct, const SpecOpKind kind)
    {
        if (ownerStruct.isGenericRoot() && !ownerStruct.isGenericInstance())
            return !ownerStruct.fields().empty();

        for (const SymbolVariable* field : ownerStruct.fields())
        {
            if (field && SemaSpecOp::typeHasLifecycle(sema.ctx(), field->typeRef(), kind))
                return true;
        }

        return false;
    }

    struct GeneratedLifecyclePlan
    {
        bool init     = false;
        bool drop     = false;
        bool postCopy = false;
        bool postMove = false;

        bool any() const
        {
            return init || drop || postCopy || postMove;
        }
    };

    struct PreparedGeneratedSourceView
    {
        SourceView* sourceView = nullptr;
        bool        hasError   = false;
    };

    GeneratedLifecyclePlan makeGeneratedLifecyclePlan(Sema& sema, const SymbolStruct& ownerStruct)
    {
        GeneratedLifecyclePlan plan;
        plan.init     = true;
        plan.drop     = shouldGenerateLifecycleWrapper(sema, ownerStruct, SpecOpKind::OpDrop);
        plan.postCopy = shouldGenerateLifecycleWrapper(sema, ownerStruct, SpecOpKind::OpPostCopy);
        plan.postMove = shouldGenerateLifecycleWrapper(sema, ownerStruct, SpecOpKind::OpPostMove);
        return plan;
    }

    void collectGeneratedLifecycleFieldNames(const TaskContext& ctx, const SymbolStruct& ownerStruct, SmallVector<Utf8>& outFields)
    {
        outFields.clear();
        for (const SymbolVariable* field : ownerStruct.fields())
        {
            if (field)
                outFields.push_back(field->name(ctx));
        }
    }

    void appendGeneratedLifecycleFieldCalls(Utf8& source, std::span<const Utf8> fields, const SpecOpKind kind)
    {
        const std::string_view intrinsicName = lifecycleIntrinsicName(kind);
        if (intrinsicName.empty())
            return;

        if (kind == SpecOpKind::OpDrop)
        {
            for (size_t i = fields.size(); i != 0; --i)
            {
                source += "        ";
                source += intrinsicName;
                source += "(&.";
                source += fields[i - 1];
                source += ")\n";
            }

            return;
        }

        for (const Utf8& fieldName : fields)
        {
            source += "        ";
            source += intrinsicName;
            source += "(&.";
            source += fieldName;
            source += ")\n";
        }
    }

    void appendGeneratedInitWrapper(Utf8& source)
    {
        source += "    #[Implicit]\n";
        source += "    private mtd ";
        source += SemaSpecOp::generatedInitWrapperName();
        source += "()\n";
        source += "    {\n";
        source += "        @init(me, 1)\n";
        source += "    }\n";
    }

    void appendGeneratedLifecycleWrapper(const TaskContext& ctx, Utf8& source, const SymbolStruct& ownerStruct, std::span<const Utf8> fields, const SpecOpKind kind)
    {
        const std::string_view wrapperName = SemaSpecOp::generatedLifecycleWrapperName(kind);
        SWC_ASSERT(!wrapperName.empty());

        source += "    #[Implicit]\n";
        source += "    private mtd ";
        source += wrapperName;
        source += "()\n";
        source += "    {\n";
        if (kind == SpecOpKind::OpDrop && hasDirectLifecycle(ctx, ownerStruct, kind))
        {
            source += "        .";
            source += SemaSpecOp::specOpFunctionName(kind);
            source += "()\n";
        }

        appendGeneratedLifecycleFieldCalls(source, fields, kind);

        if (kind != SpecOpKind::OpDrop && hasDirectLifecycle(ctx, ownerStruct, kind))
        {
            source += "        .";
            source += SemaSpecOp::specOpFunctionName(kind);
            source += "()\n";
        }

        source += "    }\n";
    }

    void appendGeneratedLifecycleWrappers(const TaskContext& ctx, Utf8& source, const SymbolStruct& ownerStruct, std::span<const Utf8> fields, const GeneratedLifecyclePlan& plan)
    {
        bool addSeparator = false;
        if (plan.init)
        {
            appendGeneratedInitWrapper(source);
            addSeparator = true;
        }

        if (plan.drop)
        {
            if (addSeparator)
                source += "\n";
            appendGeneratedLifecycleWrapper(ctx, source, ownerStruct, fields, SpecOpKind::OpDrop);
            addSeparator = true;
        }

        if (plan.postCopy)
        {
            if (addSeparator)
                source += "\n";
            appendGeneratedLifecycleWrapper(ctx, source, ownerStruct, fields, SpecOpKind::OpPostCopy);
            addSeparator = true;
        }

        if (plan.postMove)
        {
            if (addSeparator)
                source += "\n";
            appendGeneratedLifecycleWrapper(ctx, source, ownerStruct, fields, SpecOpKind::OpPostMove);
        }
    }

    Utf8 makeGeneratedLifecycleSource(Sema& sema, const SymbolStruct& ownerStruct, const GeneratedLifecyclePlan& plan)
    {
        if (!plan.any())
            return {};

        SmallVector<Utf8> fields;
        collectGeneratedLifecycleFieldNames(sema.ctx(), ownerStruct, fields);
        const Utf8 ownerTypeName = ownerStruct.typeInfo(sema.ctx()).toName(sema.ctx());

        Utf8 source;
        source += "// Generated lifecycle wrappers.\n";
        source += "impl ";
        source += ownerTypeName;
        source += "\n{\n";
        appendGeneratedLifecycleWrappers(sema.ctx(), source, ownerStruct, fields.span(), plan);
        source += "}\n";
        return source;
    }

    Utf8 makeGeneratedLifecycleMethodsSource(Sema& sema, const SymbolStruct& ownerStruct, const GeneratedLifecyclePlan& plan)
    {
        if (!plan.any())
            return {};

        SmallVector<Utf8> fields;
        collectGeneratedLifecycleFieldNames(sema.ctx(), ownerStruct, fields);

        Utf8 source;
        source += "// Generated lifecycle wrappers.\n";
        appendGeneratedLifecycleWrappers(sema.ctx(), source, ownerStruct, fields.span(), plan);
        return source;
    }

    Result attachDeclaredGeneratedImpls(Sema& sema, Sema& generatedSema, AstNodeRef nodeRef, SymbolStruct& ownerStruct, bool& outAttached)
    {
        if (nodeRef.isInvalid())
            return Result::Continue;

        const SemaNodeView view = generatedSema.viewSymbol(nodeRef);
        if (view.hasSymbol() && view.sym() && view.sym()->isImpl())
        {
            auto&               symImpl    = view.sym()->cast<SymbolImpl>();
            const SymbolStruct* implStruct = symImpl.isForStruct() ? symImpl.symStruct() : nullptr;
            if (symImpl.idRef() == ownerStruct.idRef() && (!implStruct || implStruct == &ownerStruct))
            {
                if (!implStruct)
                    symImpl.setSymStruct(&ownerStruct);
                ownerStruct.addImpl(sema, symImpl);
                if (!symImpl.isPendingRegistrationResolved())
                {
                    symImpl.setPendingRegistrationResolved();
                    sema.compiler().decPendingImplRegistrations(symImpl.pendingRegistrationTargetIdRef());
                }
                outAttached = true;
            }
        }

        SmallVector<AstNodeRef> children;
        generatedSema.node(nodeRef).collectChildrenFromAst(children, generatedSema.ast());
        for (const AstNodeRef childRef : children)
            SWC_RESULT(attachDeclaredGeneratedImpls(sema, generatedSema, childRef, ownerStruct, outAttached));

        return Result::Continue;
    }

    Result prepareGeneratedSourceView(Sema& sema, const std::string_view source, const SourceCodeRef& debugSourceCodeRef, PreparedGeneratedSourceView& outPrepared)
    {
        CompilerInstance& compiler        = sema.compiler();
        const SourceView& ownerSrcView    = sema.ast().srcView();
        const SourceFile* ownerSourceFile = compiler.owningSourceFile(ownerSrcView);
        SWC_ASSERT(ownerSourceFile != nullptr);

        SourceView& sourceView = compiler.addBufferedSourceView(ownerSourceFile->ref(), source);
        sourceView.setDebugSourceCodeRef(debugSourceCodeRef);
        const uint64_t errorsBefore = Stats::getNumErrors();
        Lexer          lexer;
        lexer.tokenize(sema.ctx(), sourceView, LexerFlagsE::Default);

        outPrepared.sourceView = &sourceView;
        outPrepared.hasError   = Stats::getNumErrors() != errorsBefore;
        return Result::Continue;
    }

    Result declareGeneratedOperatorSource(Sema& sema, SymbolStruct& ownerStruct, std::string_view source)
    {
        if (source.empty())
            return Result::Continue;

        TaskContext&      ctx      = sema.ctx();
        CompilerInstance& compiler = sema.compiler();

        PreparedGeneratedSourceView prepared;
        SWC_RESULT(prepareGeneratedSourceView(sema, source, ownerStruct.codeRef(), prepared));
        SourceView& srcView = *prepared.sourceView;
        if (prepared.hasError || srcView.mustSkip() || !srcView.runsSema())
            return Result::Continue;

        const uint64_t errorsBefore = Stats::getNumErrors();
        Parser         parser;
        AstNodeRef     generatedRoot = parser.parseGenerated(ctx, sema.ast(), srcView, ParserGeneratedMode::TopLevel);
        if (Stats::getNumErrors() != errorsBefore || generatedRoot.isInvalid())
            return Result::Continue;

        Sema         generatedDeclSema(ctx, sema, generatedRoot, true);
        const Result declResult = generatedDeclSema.execResult();
        SWC_ASSERT(declResult != Result::Pause);
        SWC_RESULT(declResult);

        bool attached = false;
        SWC_RESULT(attachDeclaredGeneratedImpls(sema, generatedDeclSema, generatedRoot, ownerStruct, attached));
        SWC_ASSERT(attached);

        auto* job = sema.compiler().makeJob<SemaJob>(ctx, sema, generatedRoot);
        compiler.global().jobMgr().enqueue(*job, JobPriority::Normal, compiler.jobClientId());
        compiler.notifyAlive();
        return Result::Continue;
    }

    Result declareGeneratedImplBlockSource(Sema& sema, SymbolStruct& ownerStruct, std::string_view source)
    {
        if (source.empty())
            return Result::Continue;

        TaskContext& ctx = sema.ctx();

        PreparedGeneratedSourceView prepared;
        SWC_RESULT(prepareGeneratedSourceView(sema, source, ownerStruct.codeRef(), prepared));
        SourceView& srcView = *prepared.sourceView;
        if (prepared.hasError || srcView.mustSkip() || !srcView.runsSema())
            return Result::Continue;

        const uint64_t   errorsBefore = Stats::getNumErrors();
        Parser           parser;
        const AstNodeRef generatedRoot = parser.parseGenerated(ctx, sema.ast(), srcView, ParserGeneratedMode::TopLevel);
        if (Stats::getNumErrors() != errorsBefore || generatedRoot.isInvalid())
            return Result::Continue;

        auto* symImpl = Symbol::make<SymbolImpl>(ctx, ownerStruct.decl(), ownerStruct.tokRef(), ownerStruct.idRef(), SymbolFlagsE::Zero);
        symImpl->setOwnerSymMap(ownerStruct.ownerSymMap());
        symImpl->setSymStruct(&ownerStruct);
        ownerStruct.addImpl(sema, *symImpl);

        SWC_RESULT(runGeneratedImplPass(ctx, sema, generatedRoot, *symImpl, ownerStruct.attributes(), true));
        SWC_RESULT(runGeneratedImplPass(ctx, sema, generatedRoot, *symImpl, ownerStruct.attributes(), false));
        symImpl->setDeclared(ctx);
        symImpl->setTyped(ctx);
        symImpl->setSemaCompleted(ctx);
        return Result::Continue;
    }
}

std::string_view SemaSpecOp::generatedLifecycleWrapperName(const SpecOpKind kind)
{
    switch (kind)
    {
        case SpecOpKind::OpDrop:
            return "swagLifecycleDropWrapper";
        case SpecOpKind::OpPostCopy:
            return "swagLifecyclePostcopyWrapper";
        case SpecOpKind::OpPostMove:
            return "swagLifecyclePostmoveWrapper";
        default:
            return {};
    }
}

std::string_view SemaSpecOp::generatedInitWrapperName()
{
    return "swagLifecycleInitWrapper";
}

bool SemaSpecOp::isGeneratedLifecycleWrapperName(const std::string_view name)
{
    if (name == generatedInitWrapperName())
        return true;

    return name == generatedLifecycleWrapperName(SpecOpKind::OpDrop) ||
           name == generatedLifecycleWrapperName(SpecOpKind::OpPostCopy) ||
           name == generatedLifecycleWrapperName(SpecOpKind::OpPostMove);
}

bool SemaSpecOp::typeHasLifecycle(TaskContext& ctx, TypeRef typeRef, SpecOpKind kind)
{
    std::unordered_set<TypeRef> visiting;
    return typeHasLifecycleRec(ctx, typeRef, kind, visiting);
}

Result SemaSpecOp::ensureGeneratedLifecycleFunctions(Sema& sema, SymbolStruct& ownerStruct)
{
    if (ownerStruct.generatedLifecyclePublished())
        return Result::Continue;

    const std::scoped_lock lock(ownerStruct.generatedLifecycleMutex());
    if (ownerStruct.generatedLifecyclePublished())
        return Result::Continue;

    if (hasGeneratedLifecycleWrapper(sema.ctx(), ownerStruct))
    {
        ownerStruct.publishGeneratedLifecycle();
        return Result::Continue;
    }

    if (!ownerStruct.tryMarkGeneratedLifecycleFunctions())
    {
        ownerStruct.publishGeneratedLifecycle();
        return Result::Continue;
    }

    const GeneratedLifecyclePlan plan = makeGeneratedLifecyclePlan(sema, ownerStruct);
    if (!plan.any())
    {
        ownerStruct.publishGeneratedLifecycle();
        return Result::Continue;
    }

    if (ownerStruct.isGenericInstance())
    {
        const Utf8 source = makeGeneratedLifecycleMethodsSource(sema, ownerStruct, plan);
        SWC_RESULT(declareGeneratedImplBlockSource(sema, ownerStruct, source.view()));
        ownerStruct.publishGeneratedLifecycle();
        return Result::Continue;
    }

    const Utf8 source = makeGeneratedLifecycleSource(sema, ownerStruct, plan);
    SWC_RESULT(declareGeneratedOperatorSource(sema, ownerStruct, source.view()));
    ownerStruct.publishGeneratedLifecycle();
    return Result::Continue;
}

Result SemaSpecOp::ensureGeneratedOperators(Sema& sema, SymbolStruct& ownerStruct)
{
    const GeneratedOperatorFlags flags = ownerStruct.attributes().generatedOperators;
    if (flags.none())
        return Result::Continue;

    if (ownerStruct.isGenericInstance())
        return validateGeneratedOperatorFieldSupport(sema, ownerStruct, flags);

    if (ownerStruct.generatedOperatorsPublished())
        return Result::Continue;

    const std::scoped_lock lock(ownerStruct.generatedOperatorsMutex());
    if (ownerStruct.generatedOperatorsPublished())
        return Result::Continue;

    if (!ownerStruct.tryMarkGeneratedOperators())
    {
        ownerStruct.publishGeneratedOperators();
        return Result::Continue;
    }

    SWC_RESULT(validateGeneratedOperatorDuplicates(sema, ownerStruct, flags));
    if (!ownerStruct.isGenericRoot())
        SWC_RESULT(validateGeneratedOperatorFieldSupport(sema, ownerStruct, flags));

    const Utf8 source = makeGeneratedOperatorsSource(sema, ownerStruct, flags);
    SWC_RESULT(declareGeneratedOperatorSource(sema, ownerStruct, source.view()));
    ownerStruct.publishGeneratedOperators();
    return Result::Continue;
}

SWC_END_NAMESPACE();
