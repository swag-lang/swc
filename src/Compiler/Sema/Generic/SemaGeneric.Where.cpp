#include "pch.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Cast/CastFailure.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace SemaGeneric
{
    namespace
    {
        using Internal::evalGenericConstraintNode;
        using Internal::genericDeclNodeRef;
        using Internal::genericFunctionDecl;
        using Internal::ResolvedGenericBindingSource;

        SpanRef genericStructWhereSpan(const SymbolStruct& root)
        {
            if (!root.decl())
                return SpanRef::invalid();

            const AstNode* decl = root.decl();
            if (const auto* structDecl = decl->safeCast<AstStructDecl>())
                return structDecl->spanWhereRef;
            if (const auto* unionDecl = decl->safeCast<AstUnionDecl>())
                return unionDecl->spanWhereRef;
            return SpanRef::invalid();
        }

        bool isWhereConstraint(Sema& sema, AstNodeRef constraintRef)
        {
            if (!constraintRef.isValid())
                return false;

            const AstNode& constraintNode = sema.node(constraintRef);
            return sema.token(constraintNode.codeRef()).id == TokenId::KwdWhere;
        }

        enum class GenericConstraintOutcomeKind : uint8_t
        {
            Satisfied,
            NotBool,
            NotConst,
            Failed,
        };

        struct GenericConstraintDiagnosticIds
        {
            DiagnosticId notBool  = DiagnosticId::None;
            DiagnosticId notConst = DiagnosticId::None;
            DiagnosticId failed   = DiagnosticId::None;
        };

        struct GenericConstraintContext
        {
            const Symbol*                            root = nullptr;
            std::span<const SemaClone::ParamBinding> bindings;
            SpanRef                                  spanWhereRef = SpanRef::invalid();
            AstNodeRef                               mainRef      = AstNodeRef::invalid();
            std::string_view                         symbolName;
            const Utf8*                              bindingText = nullptr;
            GenericConstraintDiagnosticIds           diagIds;
        };

        struct GenericConstraintOutcome
        {
            GenericConstraintOutcomeKind kind    = GenericConstraintOutcomeKind::Satisfied;
            TypeRef                      typeRef = TypeRef::invalid();
        };

        GenericConstraintContext makeFunctionConstraintContext(Sema& sema, const SymbolFunction& function, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef errorNodeRef, const Utf8& bindingText)
        {
            GenericConstraintContext context;
            context.root        = &function;
            context.bindings    = bindings;
            context.mainRef     = errorNodeRef.isValid() ? errorNodeRef : function.declNodeRef();
            context.symbolName  = function.name(sema.ctx());
            context.bindingText = &bindingText;
            context.diagIds     = {
                    .notBool  = DiagnosticId::sema_err_function_where_not_bool,
                    .notConst = DiagnosticId::sema_err_function_where_not_const,
                    .failed   = DiagnosticId::sema_err_function_where_failed,
            };
            if (const auto* decl = genericFunctionDecl(function))
                context.spanWhereRef = decl->spanConstraintsRef;
            return context;
        }

        GenericConstraintContext makeStructConstraintContext(Sema& sema, const SymbolStruct& root, std::span<const SemaClone::ParamBinding> bindings, AstNodeRef errorNodeRef, const Utf8& bindingText)
        {
            GenericConstraintContext context;
            context.root         = &root;
            context.bindings     = bindings;
            context.spanWhereRef = genericStructWhereSpan(root);
            context.mainRef      = errorNodeRef.isValid() ? errorNodeRef : root.declNodeRef();
            context.symbolName   = root.name(sema.ctx());
            context.bindingText  = &bindingText;
            context.diagIds      = {
                     .notBool  = DiagnosticId::sema_err_generic_struct_where_not_bool,
                     .notConst = DiagnosticId::sema_err_generic_struct_where_not_const,
                     .failed   = DiagnosticId::sema_err_generic_struct_where_failed,
            };
            return context;
        }

        bool hasGenericConstraintBindingText(const GenericConstraintContext& context)
        {
            return context.bindingText && !context.bindingText->empty();
        }

        DiagnosticId genericConstraintDiagId(const GenericConstraintContext& context, const GenericConstraintOutcomeKind outcomeKind)
        {
            switch (outcomeKind)
            {
                case GenericConstraintOutcomeKind::NotBool:
                    return context.diagIds.notBool;
                case GenericConstraintOutcomeKind::NotConst:
                    return context.diagIds.notConst;
                case GenericConstraintOutcomeKind::Failed:
                    return context.diagIds.failed;
                case GenericConstraintOutcomeKind::Satisfied:
                    break;
            }

            SWC_UNREACHABLE();
        }

        GenericConstraintOutcome classifyGenericConstraintOutcome(Sema& sema, const SemaNodeView& whereView)
        {
            if (!whereView.cstRef().isValid() && !whereView.typeRef().isValid())
                return {.kind = GenericConstraintOutcomeKind::NotConst};
            if (!whereView.typeRef().isValid() || !whereView.type()->isBool())
                return {.kind = GenericConstraintOutcomeKind::NotBool, .typeRef = whereView.typeRef()};
            if (!whereView.cstRef().isValid())
                return {.kind = GenericConstraintOutcomeKind::NotConst};
            if (whereView.cstRef() != sema.cstMgr().cstTrue())
                return {.kind = GenericConstraintOutcomeKind::Failed};
            return {};
        }

        Diagnostic reportGenericConstraintDiag(Sema& sema, DiagnosticId diagId, const GenericConstraintContext& context, AstNodeRef whereRef)
        {
            SWC_ASSERT(context.mainRef.isValid());
            auto diag = SemaError::report(sema, diagId, context.mainRef);
            diag.addArgument(Diagnostic::ARG_SYM, context.symbolName);

            if (hasGenericConstraintBindingText(context))
            {
                diag.addNote(DiagnosticId::sema_note_generic_instantiated_with);
                diag.last().addArgument(Diagnostic::ARG_VALUES, *context.bindingText);
            }

            if (whereRef.isValid())
            {
                diag.addNote(DiagnosticId::sema_note_generic_where_declared_here);
                SemaError::addSpan(sema, diag.last(), whereRef);
            }

            return diag;
        }

        void fillGenericConstraintFailure(Sema& sema, CastFailure& outFailure, const GenericConstraintContext& context, AstNodeRef whereRef, const GenericConstraintOutcome& outcome)
        {
            outFailure            = {};
            outFailure.diagId     = genericConstraintDiagId(context, outcome.kind);
            outFailure.srcTypeRef = outcome.typeRef;
            if (whereRef.isValid())
                outFailure.noteCodeRef = sema.node(whereRef).codeRef();
            if (hasGenericConstraintBindingText(context))
                outFailure.addArgument(Diagnostic::ARG_VALUES, *context.bindingText);
        }

        Result reportGenericConstraintFailure(Sema& sema, const GenericConstraintContext& context, AstNodeRef whereRef, const GenericConstraintOutcome& outcome)
        {
            auto diag = reportGenericConstraintDiag(sema, genericConstraintDiagId(context, outcome.kind), context, whereRef);
            if (outcome.kind == GenericConstraintOutcomeKind::NotBool)
                diag.addArgument(Diagnostic::ARG_TYPE, outcome.typeRef.isValid() ? sema.typeMgr().get(outcome.typeRef).toName(sema.ctx()) : Utf8{"<invalid>"});
            diag.report(sema.ctx());
            return Result::Error;
        }

        Result evaluateGenericWhereConstraints(Sema& sema, bool& outSatisfied, const GenericConstraintContext& context, CastFailure* outFailure)
        {
            outSatisfied = true;
            if (!context.root || context.spanWhereRef.isInvalid())
                return Result::Continue;

            SmallVector<AstNodeRef> constraintRefs;
            sema.ast().appendNodes(constraintRefs, context.spanWhereRef);
            for (const AstNodeRef constraintRef : constraintRefs)
            {
                if (!isWhereConstraint(sema, constraintRef))
                    continue;

                AstNodeRef evalRef = AstNodeRef::invalid();
                SWC_RESULT(evalGenericConstraintNode(sema, *context.root, constraintRef, context.bindings, evalRef));
                if (evalRef.isInvalid())
                    continue;

                const GenericConstraintOutcome outcome = classifyGenericConstraintOutcome(sema, sema.viewNodeTypeConstant(evalRef));
                if (outcome.kind == GenericConstraintOutcomeKind::Satisfied)
                    continue;

                outSatisfied = false;
                if (outFailure)
                {
                    fillGenericConstraintFailure(sema, *outFailure, context, constraintRef, outcome);
                    return Result::Continue;
                }

                return reportGenericConstraintFailure(sema, context, constraintRef, outcome);
            }

            return Result::Continue;
        }

    }

    namespace Internal
    {
        Result checkFunctionWhereConstraints(Sema& sema, bool& outSatisfied, const SymbolFunction& function, std::span<const SemaClone::ParamBinding> bindings, const Utf8& bindingText, CastFailure* outFailure, AstNodeRef errorNodeRef)
        {
            const GenericConstraintContext context = makeFunctionConstraintContext(sema, function, bindings, errorNodeRef, bindingText);
            return evaluateGenericWhereConstraints(sema, outSatisfied, context, outFailure);
        }

        Result validateGenericStructWhereConstraints(Sema& sema, const SymbolStruct& root, std::span<const GenericParamDesc> params, std::span<const GenericResolvedArg> resolvedArgs, AstNodeRef errorNodeRef)
        {
            const ResolvedGenericBindingSource   source{params, resolvedArgs};
            SmallVector<SemaClone::ParamBinding> bindings;
            buildResolvedGenericContextBindings(sema, root, source, bindings);

            const Utf8                     bindingText = params.empty() ? Utf8{} : formatResolvedGenericBindings(sema, source);
            const GenericConstraintContext context     = makeStructConstraintContext(sema, root, bindings.span(), errorNodeRef, bindingText);
            bool                           satisfied   = true;
            return evaluateGenericWhereConstraints(sema, satisfied, context, nullptr);
        }
    }
}

namespace SemaGeneric
{
    Result evaluateFunctionWhereConstraints(Sema& sema, bool& outSatisfied, const SymbolFunction& function, CastFailure* outFailure)
    {
        outSatisfied     = true;
        const auto* decl = genericFunctionDecl(function);
        if (!decl || decl->spanConstraintsRef.isInvalid())
            return Result::Continue;

        std::unique_ptr<Sema> sourceSemaHolder;
        Sema*                 sourceSema = Internal::tryCreateSemaForGenericDecl(sema, function, sourceSemaHolder);
        if (!sourceSema)
            sourceSema = &sema;

        Internal::FunctionWhereInputs whereInputs;
        Internal::buildFunctionWhereInputs(*sourceSema, function, whereInputs);
        return Internal::checkFunctionWhereConstraints(*sourceSema, outSatisfied, function, whereInputs.bindings.span(), whereInputs.bindingText, outFailure, genericDeclNodeRef(function));
    }
}

SWC_END_NAMESPACE();
