#include "pch.h"
#include "Compiler/Sema/Helpers/SemaInitFlow.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Switch.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_MAX_TRACKED_VARS = 48;
    constexpr uint32_t K_MAX_NODES        = 200000;
    constexpr uint32_t K_MAX_ERRORS       = 8;
    constexpr uint64_t K_ALL_BITS         = ~0ull;

    bool isFullInitializationSetter(const SymbolFunction* calledFn)
    {
        if (!calledFn)
            return false;
        if (calledFn->specOpKind() != SpecOpKind::OpSet && calledFn->specOpKind() != SpecOpKind::OpSetLiteral)
            return false;
        return calledFn->hasFullInitialization();
    }

    // One local participating in initialization flow. It either has a safe default
    // that may be elided, or requires a proof before it can be observed. Fields of a
    // struct local are tracked individually (one bit each, capped at 63); every other
    // type is a single slot (bit 0).
    struct TrackedVar
    {
        SymbolVariable*       sym         = nullptr;
        const SymbolStruct*   fieldStruct = nullptr; // set when fields are tracked individually
        uint32_t              fieldCount  = 0;       // 0 => single slot
        uint64_t              fullMask    = 1;
        uint64_t              dropMask    = 0; // bits of fields with a drop lifecycle
        uint64_t              lateMask    = 0; // bits of 'Swag.Late' fields ('lateOnly' tracking)
        bool                  typeHasDrop = false;
        bool                  isRetVal    = false;
        bool                  lateOnly    = false; // tracked only for its 'Swag.Late' fields: regular zero-initialized storage
        bool                  defaultInitCandidate = false;
        bool                  needsDefiniteInit = false;
        bool                  fullInitReceiver = false;
        bool                  errored     = false; // one report per variable
        SmallVector<AstNodeRef, 4> firstInitAssignRefs;
        uint32_t              blockDepth  = 0;
        uint32_t              loopDepth   = 0;
    };

    // Per-path init state: two bitsets per tracked var, parallel to the tracked list.
    // 'must' = initialized on every path reaching this point (governs reads and drop
    // points); 'may' = initialized on at least one path (a drop may only be elided
    // when even 'may' is empty). Entries beyond a state's size behave as K_ALL_BITS
    // (variable not in scope on that path, hence inert).
    struct FlowState
    {
        SmallVector<uint64_t, 8> must;
        SmallVector<uint64_t, 8> may;

        uint64_t getMust(uint32_t i) const { return i < must.size() ? must[i] : K_ALL_BITS; }
        uint64_t getMay(uint32_t i) const { return i < may.size() ? may[i] : K_ALL_BITS; }
        void     set(uint32_t i, uint64_t mustBits, uint64_t mayBits)
        {
            while (must.size() <= i)
            {
                must.push_back(K_ALL_BITS);
                may.push_back(K_ALL_BITS);
            }
            must[i] = mustBits;
            may[i]  = mayBits;
        }
        void add(uint32_t i, uint64_t bits) { set(i, getMust(i) | bits, getMay(i) | bits); }
    };

    void joinInto(FlowState& dst, const FlowState& src)
    {
        const uint32_t common = std::min(dst.must.size32(), src.must.size32());
        for (uint32_t i = 0; i < common; i++)
        {
            dst.must[i] &= src.must[i];
            dst.may[i] |= src.may[i];
        }
        // Entries only one side has behave as K_ALL_BITS on the other: the 'must'
        // intersection keeps them, the 'may' union saturates them.
        for (uint32_t i = common; i < dst.may.size32(); i++)
            dst.may[i] = K_ALL_BITS;
    }

    enum class FlowExit : uint8_t
    {
        Normal,
        Jumped, // return / fail / break / continue / unreachable
        Fell,   // 'fallthrough' out of a switch case body
    };

    // A breakable construct (loop or switch) currently being walked.
    struct BreakCtx
    {
        bool                      acceptsContinue = false;
        uint32_t                  blockDepth      = 0;
        SmallVector<FlowState, 2> breakStates;
    };

    class Walker
    {
    public:
        Walker(Sema& sema, const SymbolFunction& sym, bool checkReturnContract) :
            sema_(&sema),
            sym_(&sym)
        {
            returnContract_ = checkReturnContract && isNullableTypeRef(sym.returnTypeRef());
        }

        Result run(AstNodeRef bodyRef)
        {
            FlowState state;
            trackFullInitReceiver(state);
            const FlowExit exit = walk(bodyRef, state);
            if (exit == FlowExit::Normal)
                checkFullInitExit(state);

            if (!aborted_)
            {
                for (const TrackedVar& var : vars_)
                {
                    if (var.fullInitReceiver)
                    {
                        if (var.defaultInitCandidate && firstInitializersCanConstruct(var))
                        {
                            sym_->setInferredFullInitialization(true);
                            markInitialAssignmentsAsConstruction(var);
                        }
                        continue;
                    }

                    // A type with no safe default reaches codegen only after this
                    // pass has proved that every observation is preceded by a write.
                    // The same flag prevents materializing an impossible default.
                    if (var.needsDefiniteInit)
                    {
                        var.sym->addExtraFlag(SymbolVariableFlagsE::DefaultInitElided);
                        continue;
                    }

                    // This is deliberately a late lowering decision: semantic
                    // resolution tells us whether an initial assignment is an
                    // ordinary store or a user opSet. We only omit storage
                    // initialization when every first write constructs the value.
                    if (var.defaultInitCandidate && firstInitializersCanConstruct(var))
                    {
                        var.sym->addExtraFlag(SymbolVariableFlagsE::DefaultInitElided);
                        markInitialAssignmentsAsConstruction(var);
                    }
                }
            }

            // A '#null' return type that no return path can produce promises a null
            // that never happens: callers pay guards for nothing.
            if (returnContract_ && returnSeen_ && !mayReturnNull_ && !aborted_)
            {
                hadError_ = true;
                auto diag = SemaError::report(*sema_, DiagnosticId::sema_err_nullable_return_contract, *sym_);
                SemaError::setReportArguments(*sema_, diag, sym_);
                diag.report(sema_->ctx());
            }

            // A local annotated '#null' whose every incoming value is provably
            // non-null (and whose address never escapes) wears a dead qualifier.
            if (!aborted_)
            {
                for (const NullableLocal& local : nullableLocals_)
                {
                    if (!local.sawValue || local.keepNull)
                        continue;
                    hadError_ = true;
                    auto diag = SemaError::report(*sema_, DiagnosticId::sema_err_nullable_local_contract, *local.sym);
                    SemaError::setReportArguments(*sema_, diag, local.sym);
                    diag.report(sema_->ctx());
                }
            }

            return hadError_ ? Result::Error : Result::Continue;
        }

    private:
        Sema*                   sema_ = nullptr;
        const SymbolFunction*   sym_  = nullptr;
        std::vector<TrackedVar> vars_;
        std::vector<BreakCtx*>  breakables_;
        SmallVector<int32_t, 4> withTargets_; // tracked index or -1, innermost last
        uint32_t                blockDepth_   = 0;
        uint32_t                loopDepth_    = 0;
        uint32_t                deferDepth_   = 0;
        uint32_t                handledDepth_ = 0; // catch/expect wrappers
        uint32_t                inlineDepth_  = 0; // inline/mixin expansions: 'return' exits the expansion, not the function
        uint32_t                nodeCount_    = 0;
        uint32_t                errorCount_   = 0;
        bool                    aborted_      = false;
        bool                    hadError_     = false;
        int32_t                 fullInitReceiverIndex_ = -1;
        // '#null' return contract tracking.
        bool returnContract_ = false;
        bool returnSeen_     = false;
        bool mayReturnNull_  = false;
        // '#null' local contract tracking (function-global, not path-based): a local
        // is reported when every value it can ever hold is provably non-null.
        struct NullableLocal
        {
            const SymbolVariable* sym      = nullptr;
            bool                  keepNull = false; // saw a possibly-null value or an escape
            bool                  sawValue = false;
        };
        SmallVector<NullableLocal, 8> nullableLocals_;

        int32_t nullableLocalIndex(const SymbolVariable* sym) const
        {
            if (!sym)
                return -1;
            for (uint32_t i = 0; i < nullableLocals_.size32(); i++)
            {
                if (nullableLocals_[i].sym == sym)
                    return static_cast<int32_t>(i);
            }
            return -1;
        }

        // Shape-based proof that an expression's value cannot be null (the nodes are
        // retyped in place by implicit widening, so declared types are consulted).
        bool valueShapeIsNonNull(AstNodeRef exprRef) const
        {
            const AstNodeRef ref = unwrap(exprRef);
            if (ref.isInvalid())
                return false;

            const AstNode& node = sema_->node(ref);
            switch (node.id())
            {
                case AstNodeId::UnaryExpr:
                    return tokenIdOf(node, TokenId::SymLeftBracket) == TokenId::SymAmpersand;

                case AstNodeId::Identifier:
                {
                    const SymbolVariable* symVar = identifierVariable(ref);
                    return symVar && isNonNullPointerLikeTypeRef(symVar->typeRef());
                }

                case AstNodeId::CallExpr:
                case AstNodeId::IntrinsicCallExpr:
                {
                    const SemaNodeView view = sema_->viewSymbol(ref);
                    Symbol*            sym  = view.hasSymbol() ? view.singleSymbol() : nullptr;
                    return sym && sym->isFunction() && isNonNullPointerLikeTypeRef(sym->cast<SymbolFunction>().returnTypeRef());
                }

                case AstNodeId::ErrorManagementExpr:
                    // 'notnull x' asserts non-null; other wrappers stay conservative.
                    return tokenIdOf(node, TokenId::KwdCatch) == TokenId::SymBang &&
                           valueShapeIsNonNull(node.cast<AstErrorManagementExpr>().nodeExprRef);

                default:
                    return false;
            }
        }
        // Active recursion stack: a child ref can resolve back to an ancestor through
        // the substitution table (self-substituted casts); never re-enter one.
        SmallVector<AstNodeRef, 32> activeRefs_;

        bool isActiveRef(AstNodeRef ref) const
        {
            for (const AstNodeRef activeRef : activeRefs_)
            {
                if (activeRef == ref)
                    return true;
            }
            return false;
        }

        // -------------------------------------------------------------------------

        AstNodeRef resolve(AstNodeRef ref) const
        {
            if (ref.isInvalid())
                return ref;
            const AstNodeRef resolved = sema_->viewZero(ref).nodeRef();
            return resolved.isValid() ? resolved : ref;
        }

        // Compiler-generated nodes can carry an invalid source reference: never feed
        // one to Sema::token().
        TokenId tokenIdOf(const AstNode& node, TokenId fallback) const
        {
            const SourceCodeRef& codeRef = node.codeRef();
            if (!codeRef.isValid())
                return fallback;
            return sema_->token(codeRef).id;
        }

        // Skips wrappers that are transparent for data flow. Resolution cycles
        // (an operand substituted by its own wrapper) fall back to the raw node.
        AstNodeRef unwrap(AstNodeRef ref) const
        {
            SmallVector<AstNodeRef, 8> seen;
            for (uint32_t guard = 0; guard < 64; guard++)
            {
                const AstNodeRef rawRef      = ref;
                const AstNodeRef resolvedRef = resolve(ref);
                bool             cycles      = false;
                for (const AstNodeRef seenRef : seen)
                {
                    if (seenRef == resolvedRef)
                    {
                        cycles = true;
                        break;
                    }
                }
                ref = cycles ? rawRef : resolvedRef;
                if (ref.isInvalid())
                    return ref;
                if (!cycles)
                    seen.push_back(ref);
                const AstNode& node = sema_->node(ref);
                switch (node.id())
                {
                    case AstNodeId::ParenExpr:
                        ref = node.cast<AstParenExpr>().nodeExprRef;
                        break;
                    case AstNodeId::InitializerExpr:
                        ref = node.cast<AstInitializerExpr>().nodeExprRef;
                        break;
                    case AstNodeId::AutoCastExpr:
                        ref = node.cast<AstAutoCastExpr>().nodeExprRef;
                        break;
                    case AstNodeId::CastExpr:
                        ref = node.cast<AstCastExpr>().nodeExprRef;
                        break;
                    case AstNodeId::AsCastExpr:
                        ref = node.cast<AstAsCastExpr>().nodeExprRef;
                        break;
                    case AstNodeId::NamedArgument:
                        ref = node.cast<AstNamedArgument>().nodeArgRef;
                        break;
                    default:
                        return ref;
                }
            }
            return ref;
        }

        const SymbolVariable* identifierVariable(AstNodeRef ref) const
        {
            if (ref.isInvalid())
                return nullptr;
            const SemaNodeView view = sema_->viewSymbol(ref);
            Symbol*            sym  = view.hasSymbol() ? view.singleSymbol() : nullptr;
            if (!sym || !sym->isVariable())
                return nullptr;
            return &sym->cast<SymbolVariable>();
        }

        int32_t trackedIndex(const SymbolVariable* sym) const
        {
            if (!sym)
                return -1;
            for (uint32_t i = 0; i < vars_.size(); i++)
            {
                if (vars_[i].sym == sym)
                    return static_cast<int32_t>(i);
            }
            return -1;
        }

        // Resolved access path: a tracked root plus at most one first-level field.
        struct AccessPath
        {
            int32_t varIndex    = -1;
            int32_t fieldIndex  = -1; // -1 => whole variable
            bool    indexed     = false;
            bool    nestedField = false; // access goes deeper than the first-level field
        };

        // Extracts (root var, first-level field) from an lvalue-ish expression.
        // Returns false when the expression does not root at a tracked variable.
        bool accessPath(AstNodeRef ref, AccessPath& out) const
        {
            out = {};
            ref = unwrap(ref);
            if (ref.isInvalid())
                return false;

            SmallVector<const Symbol*, 4> fieldChain; // outermost access last
            for (uint32_t guard = 0; guard < 64; guard++)
            {
                const AstNode& node = sema_->node(ref);
                switch (node.id())
                {
                    case AstNodeId::Identifier:
                    {
                        const int32_t idx = trackedIndex(identifierVariable(ref));
                        if (idx < 0)
                            return false;
                        out.varIndex = idx;
                        if (!fieldChain.empty())
                        {
                            out.fieldIndex  = fieldIndexOf(vars_[idx], fieldChain.back());
                            out.nestedField = fieldChain.size() > 1;
                        }
                        return true;
                    }
                    case AstNodeId::MemberAccessExpr:
                    {
                        const auto&        member   = node.cast<AstMemberAccessExpr>();
                        const Symbol*      fieldSym = nullptr;
                        const SemaNodeView view     = sema_->viewSymbol(member.nodeRightRef);
                        if (view.hasSymbol())
                            fieldSym = view.singleSymbol();
                        fieldChain.push_back(fieldSym);
                        ref = unwrap(member.nodeLeftRef);
                        if (ref.isInvalid())
                            return false;
                        break;
                    }
                    case AstNodeId::AutoMemberAccessExpr:
                    {
                        // Attribute an implicit receiver to an explicit 'with' target,
                        // or to the receiver of an opSet being analyzed.
                        if (withTargets_.empty() && fullInitReceiverIndex_ < 0)
                            return false;
                        out.varIndex                  = withTargets_.empty() ? fullInitReceiverIndex_ : withTargets_.back();
                        if (out.varIndex < 0)
                            return false;
                        const auto&        autoMember = node.cast<AstAutoMemberAccessExpr>();
                        const AstNodeRef   identRef   = autoMember.nodeIdentRef.isValid() ? autoMember.nodeIdentRef : ref;
                        const SemaNodeView view       = sema_->viewSymbol(identRef);
                        const Symbol*      fieldSym   = view.hasSymbol() ? view.singleSymbol() : nullptr;
                        out.fieldIndex                = fieldIndexOf(vars_[out.varIndex], fieldSym);
                        return true;
                    }
                    case AstNodeId::IndexExpr:
                    {
                        out.indexed = true;
                        ref         = unwrap(node.cast<AstIndexExpr>().nodeExprRef);
                        if (ref.isInvalid())
                            return false;
                        break;
                    }
                    default:
                        return false;
                }
            }
            return false;
        }

        static int32_t fieldIndexOf(const TrackedVar& var, const Symbol* fieldSym)
        {
            if (!var.fieldStruct || !fieldSym)
                return -1;
            const auto& fields = var.fieldStruct->fields();
            for (uint32_t i = 0; i < fields.size() && i < 63; i++)
            {
                if (fields[i] == fieldSym)
                    return static_cast<int32_t>(i);
            }
            return -1;
        }

        // -------------------------------------------------------------------------

        void reportLateRead(AstNodeRef atRef, TrackedVar& var, int32_t fieldIndex)
        {
            if (deferDepth_ || aborted_ || var.errored || errorCount_ >= K_MAX_ERRORS)
                return;
            var.errored = true;
            errorCount_++;
            hadError_ = true;

            auto diag = SemaError::report(*sema_, DiagnosticId::sema_err_late_read_never_set, atRef);
            SemaError::setReportArguments(*sema_, diag, var.sym);
            if (fieldIndex >= 0 && var.fieldStruct)
                diag.addArgument(Diagnostic::ARG_VALUE, Utf8{var.fieldStruct->fields()[fieldIndex]->name(sema_->ctx())});
            if (var.sym->codeRef().isValid() && var.sym->codeRef().srcViewRef == sema_->node(atRef).codeRef().srcViewRef)
                diag.last().addSpan(var.sym->codeRange(sema_->ctx()), "declared here");
            diag.report(sema_->ctx());
        }

        void reportDefiniteInitUse(AstNodeRef atRef, TrackedVar& var, int32_t fieldIndex)
        {
            if (deferDepth_ || aborted_ || var.errored || errorCount_ >= K_MAX_ERRORS)
                return;
            var.errored = true;
            errorCount_++;
            hadError_ = true;

            const DiagnosticId id = fieldIndex >= 0 ? DiagnosticId::sema_err_definite_init_field_use : DiagnosticId::sema_err_definite_init_use;
            auto               diag = SemaError::report(*sema_, id, atRef);
            SemaError::setReportArguments(*sema_, diag, var.sym);
            if (fieldIndex >= 0 && var.fieldStruct)
                diag.addArgument(Diagnostic::ARG_VALUE, Utf8{var.fieldStruct->fields()[fieldIndex]->name(sema_->ctx())});
            if (var.sym->codeRef().isValid() && var.sym->codeRef().srcViewRef == sema_->node(atRef).codeRef().srcViewRef)
                diag.last().addSpan(var.sym->codeRange(sema_->ctx()), "declared here");
            diag.report(sema_->ctx());
        }

        void reportDefiniteInitDrop(AstNodeRef atRef, TrackedVar& var)
        {
            if (deferDepth_ || aborted_ || var.errored || errorCount_ >= K_MAX_ERRORS)
                return;
            var.errored = true;
            errorCount_++;
            hadError_ = true;

            auto diag = SemaError::report(*sema_, DiagnosticId::sema_err_definite_init_drop, atRef);
            SemaError::setReportArguments(*sema_, diag, var.sym);
            if (var.sym->codeRef().isValid() && var.sym->codeRef().srcViewRef == sema_->node(atRef).codeRef().srcViewRef)
                diag.last().addSpan(var.sym->codeRange(sema_->ctx()), "declared here");
            diag.report(sema_->ctx());
        }

        // -------------------------------------------------------------------------

        void disqualifyDefaultInitElision(FlowState& state, const uint32_t varIndex)
        {
            TrackedVar& var = vars_[varIndex];
            var.defaultInitCandidate = false;
            state.set(varIndex, var.fullMask, var.fullMask);
        }

        bool firstInitializersCanConstruct(const TrackedVar& var) const
        {
            if (var.isRetVal)
                return false;
            if (var.typeHasDrop && var.firstInitAssignRefs.empty())
                return false;

            for (const AstNodeRef assignRef : var.firstInitAssignRefs)
            {
                const auto* payload = sema_->semaPayload<AssignSpecOpPayload>(assignRef);
                if (!payload || !payload->calledFn)
                {
                    // A raw store into a type with a drop would skip the visible
                    // destruction of the ordinary default. Only a FullInit setter
                    // declares that the incoming storage is a construction site.
                    if (var.typeHasDrop)
                        return false;
                    continue;
                }

                if (!isFullInitializationSetter(payload->calledFn))
                    return false;
            }

            return true;
        }

        void markInitialAssignmentsAsConstruction(const TrackedVar& var) const
        {
            for (const AstNodeRef assignRef : var.firstInitAssignRefs)
                sema_->ast().node(assignRef).cast<AstAssignStmt>().modifierFlags.add(AstModifierFlagsE::FirstInit);
        }

        void markInit(FlowState& state, const AccessPath& path) const
        {
            if (deferDepth_)
                return;
            const TrackedVar& var = vars_[path.varIndex];
            if (path.fieldIndex >= 0)
                state.add(path.varIndex, 1ull << path.fieldIndex);
            else
            {
                // Whole assignment: the source's 'Swag.Late' fields may legally be
                // unset, so the copy proves nothing for them.
                state.set(path.varIndex, var.fullMask & ~var.lateMask, var.fullMask);
            }
        }

        void markEscaped(FlowState& state, AstNodeRef atRef, const AccessPath& path)
        {
            TrackedVar& var = vars_[path.varIndex];
            if (var.needsDefiniteInit)
            {
                // An unknown callee may read through the escaped address before it
                // writes. Require a real initialized value rather than guessing that
                // every address-taking use is an out parameter.
                checkRead(state, atRef, path);
                return;
            }
            if (var.defaultInitCandidate)
            {
                // An escaped address can observe the language-mandated default before
                // any later store. Keep that default when the callee contract is not
                // available to this pass.
                disqualifyDefaultInitElision(state, static_cast<uint32_t>(path.varIndex));
                return;
            }

            // 'Swag.Late' fields only gain 'may': the callee filling them is possible,
            // never proven (the runtime read guard stays).
            if (path.fieldIndex >= 0)
            {
                const uint64_t bit = 1ull << path.fieldIndex;
                if (var.lateMask & bit)
                    state.set(path.varIndex, state.getMust(path.varIndex), state.getMay(path.varIndex) | bit);
                else
                    state.add(path.varIndex, bit);
            }
            else
                state.set(path.varIndex, state.getMust(path.varIndex) | (var.fullMask & ~var.lateMask), var.fullMask);
        }

        bool isNullableTypeRef(TypeRef typeRef) const
        {
            if (!typeRef.isValid())
                return false;
            const TypeInfo& type = sema_->typeMgr().get(typeRef);
            if (type.isNullable())
                return true;
            const TypeRef unwrapped = sema_->typeMgr().unwrapAliasEnum(sema_->ctx(), typeRef);
            return unwrapped.isValid() && sema_->typeMgr().get(unwrapped).isNullable();
        }

        bool isNonNullPointerLikeTypeRef(TypeRef typeRef) const
        {
            if (!typeRef.isValid() || isNullableTypeRef(typeRef))
                return false;
            TypeRef       finalTypeRef = typeRef;
            const TypeRef unwrapped    = sema_->typeMgr().unwrapAliasEnum(sema_->ctx(), typeRef);
            if (unwrapped.isValid())
                finalTypeRef = unwrapped;
            const TypeInfo& type = sema_->typeMgr().get(finalTypeRef);
            return type.isPointerLike() || type.isReference();
        }

        // Records whether a function-level return can produce a null value. The
        // returned expression is widened IN PLACE to the declared '#null' type, so
        // the proof works on the expression's SHAPE: an address-of is never null, an
        // identifier follows its declared type, a call follows the callee's declared
        // return type. Everything else conservatively counts as nullable.
        void noteReturnValue(AstNodeRef exprRef)
        {
            if (!returnContract_ || deferDepth_ || mayReturnNull_)
                return;
            if (exprRef.isInvalid())
                return;
            returnSeen_ = true;

            if (!valueShapeIsNonNull(exprRef))
                mayReturnNull_ = true;
        }

        void checkRead(FlowState& state, AstNodeRef atRef, const AccessPath& path)
        {
            if (deferDepth_)
                return;
            TrackedVar& var = vars_[path.varIndex];

            // 'Swag.Late' field read: proven set on EVERY path elides the runtime read
            // guard; proven never set on ANY path is a compile-time fault; anything
            // in between is the runtime guard's business. Indexed and nested
            // accesses dereference the late field the same way.
            if (path.fieldIndex >= 0 && (var.lateMask & (1ull << path.fieldIndex)))
            {
                const uint64_t fieldBit = 1ull << path.fieldIndex;
                if (state.getMust(path.varIndex) & fieldBit)
                    SemaHelpers::clearLateFieldReadGuard(*sema_, atRef);
                else if (!(state.getMay(path.varIndex) & fieldBit))
                {
                    reportLateRead(atRef, var, path.fieldIndex);
                    state.add(path.varIndex, fieldBit); // suppress cascading reports
                }
                return;
            }

            if (!var.defaultInitCandidate)
            {
                if (!var.needsDefiniteInit)
                    return;

                const uint64_t bits = state.getMust(path.varIndex);
                if (path.fieldIndex >= 0 && (bits & (1ull << path.fieldIndex)))
                    return;
                if (path.fieldIndex < 0 && (bits & var.fullMask) == var.fullMask)
                    return;
                reportDefiniteInitUse(atRef, var, path.fieldIndex);
                state.set(path.varIndex, var.fullMask, var.fullMask);
                return;
            }

            const uint64_t bits = state.getMust(path.varIndex);
            if ((bits & var.fullMask) == var.fullMask)
                return;

            // Any read that is not fully covered observes the default value. This is
            // not an error: it simply makes initialization observable again.
            disqualifyDefaultInitElision(state, static_cast<uint32_t>(path.varIndex));
        }

        // A drop of 'var' may run at 'atRef' (reassign, scope exit, error unwind):
        // every droppable part must be initialized.
        void checkDroppable(FlowState& state, AstNodeRef atRef, uint32_t varIndex)
        {
            if (deferDepth_)
                return;
            TrackedVar& var = vars_[varIndex];
            if (!var.typeHasDrop || var.isRetVal)
                return;
            const uint64_t bits = state.getMust(varIndex);
            if ((bits & var.dropMask) == var.dropMask)
                return;
            if (var.needsDefiniteInit)
            {
                reportDefiniteInitDrop(atRef, var);
                state.set(varIndex, var.fullMask, var.fullMask);
                return;
            }
            if (!var.defaultInitCandidate)
                return;
            disqualifyDefaultInitElision(state, varIndex);
        }

        // Drops triggered by an exit: all live droppable vars declared strictly
        // deeper than 'minBlockDepth'.
        void checkDropsOnExit(FlowState& state, AstNodeRef atRef, uint32_t minBlockDepth)
        {
            for (uint32_t i = 0; i < vars_.size(); i++)
            {
                if (vars_[i].blockDepth > minBlockDepth)
                    checkDroppable(state, atRef, i);
            }
        }

        // -------------------------------------------------------------------------

        void trackFullInitReceiver(FlowState& state)
        {
            if (sym_->specOpKind() != SpecOpKind::OpSet && sym_->specOpKind() != SpecOpKind::OpSetLiteral)
                return;
            if (sym_->parameters().empty())
                return;

            SymbolVariable* receiver = sym_->parameters().front();
            const SymbolStruct* owner = sym_->ownerStruct();
            if (!receiver || !owner || !owner->isSemaCompleted() || owner->fields().empty() || owner->fields().size() > 63)
                return;

            TrackedVar var;
            var.sym                  = receiver;
            var.fieldStruct          = owner;
            var.fieldCount           = static_cast<uint32_t>(owner->fields().size());
            var.fullMask             = (1ull << var.fieldCount) - 1;
            var.defaultInitCandidate = true;
            var.fullInitReceiver     = true;

            // The null sentinel of a late field is observable, so a setter of this
            // type cannot replace default construction wholesale.
            for (const SymbolVariable* field : owner->fields())
            {
                if (field && field->hasExtraFlag(SymbolVariableFlagsE::LateInit))
                    return;
            }

            fullInitReceiverIndex_ = static_cast<int32_t>(vars_.size());
            vars_.push_back(std::move(var));
            state.set(static_cast<uint32_t>(fullInitReceiverIndex_), 0, 0);
        }

        void checkFullInitExit(const FlowState& state)
        {
            if (fullInitReceiverIndex_ < 0)
                return;

            TrackedVar& receiver = vars_[fullInitReceiverIndex_];
            if ((state.getMust(static_cast<uint32_t>(fullInitReceiverIndex_)) & receiver.fullMask) != receiver.fullMask)
                receiver.defaultInitCandidate = false;
        }

        // -------------------------------------------------------------------------

        void trackDecl(FlowState& state, AstNodeRef declRef, SymbolVariable& symVar, bool hasInitExpr)
        {
            if (deferDepth_)
                return;
            if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) || symVar.hasGlobalStorage())
                return;
            const bool needsDefiniteInit = symVar.hasExtraFlag(SymbolVariableFlagsE::NeedsDefiniteInit);
            if (!needsDefiniteInit && hasInitExpr)
                return;

            if (vars_.size() >= K_MAX_TRACKED_VARS)
            {
                aborted_ = true;
                return;
            }

            SWC_UNUSED(declRef);
            TrackedVar var;
            var.sym        = &symVar;
            var.isRetVal   = symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal);
            var.blockDepth = blockDepth_;
            var.loopDepth  = loopDepth_;
            // A mixin expansion is caller text, and the declaration's symbol may
            // be shared with another expansion. It still needs definite-init
            // checking, but cannot carry a reusable default-elision fact.
            var.defaultInitCandidate = !needsDefiniteInit && inlineDepth_ == 0;
            var.needsDefiniteInit    = needsDefiniteInit;

            uint64_t      presetBits = 0;
            const TypeRef typeRef    = symVar.typeRef();
            if (!typeRef.isValid())
                return;

            const TypeGen::LifecycleFlags lifecycle = TypeGen::lifecycleFlagsOfTypeRef(sema_->ctx(), typeRef);
            var.typeHasDrop                         = lifecycle.hasDrop;

            const TypeInfo& type           = sema_->typeMgr().get(typeRef);
            TypeRef         storageTypeRef = typeRef;
            if (const TypeRef unwrapped = type.unwrap(sema_->ctx(), typeRef, TypeExpandE::Alias); unwrapped.isValid())
                storageTypeRef = unwrapped;
            const TypeInfo& storageType = sema_->typeMgr().get(storageTypeRef);

            // Element-wise coverage needs a dedicated range analysis. A static array
            // with no safe default is nevertheless a useful single construction unit:
            // a whole-object assignment or 'Swag.init(values)' proves it initialized,
            // while an indexed write stays conservative below.
            if (storageType.isArray())
            {
                if (!var.needsDefiniteInit)
                    return;
                var.dropMask = var.typeHasDrop ? var.fullMask : 0;
            }

            if (storageType.isStruct())
            {
                const SymbolStruct& symStruct = storageType.payloadSymStruct();
                if (!symStruct.isSemaCompleted() || symStruct.fields().empty() || symStruct.fields().size() > 63)
                    return;

                var.fieldStruct = &symStruct;
                var.fieldCount  = static_cast<uint32_t>(symStruct.fields().size());
                var.fullMask    = (1ull << var.fieldCount) - 1;
                if (symStruct.opDrop() != nullptr)
                {
                    // The struct's own opDrop may read every field.
                    var.dropMask = var.fullMask;
                }
                else
                {
                    for (uint32_t i = 0; i < var.fieldCount; i++)
                    {
                        const TypeRef fieldTypeRef = symStruct.fields()[i]->typeRef();
                        if (fieldTypeRef.isValid() && TypeGen::lifecycleFlagsOfTypeRef(sema_->ctx(), fieldTypeRef).hasDrop)
                            var.dropMask |= 1ull << i;
                    }
                }

                uint64_t lateMask = 0;
                for (uint32_t i = 0; i < var.fieldCount; i++)
                {
                    if (symStruct.fields()[i]->hasExtraFlag(SymbolVariableFlagsE::LateInit))
                        lateMask |= 1ull << i;
                }
                if (lateMask)
                {
                    // The null sentinel of a late field is observable through
                    // Swag.isSet, so it remains normally initialized.
                    var.defaultInitCandidate = false;
                    var.lateOnly             = true;
                    var.lateMask             = lateMask;
                    var.dropMask &= ~lateMask;
                    presetBits = var.fullMask & ~lateMask;
                }
            }
            else
            {
                // Register locals already receive ordinary dead-store elimination.
                // They enter this pass only when their type has no safe implicit
                // default and every observation therefore needs a proof.
                if (!var.needsDefiniteInit)
                    return;
                var.dropMask = var.typeHasDrop ? var.fullMask : 0;
            }

            const uint32_t index = static_cast<uint32_t>(vars_.size());
            vars_.push_back(var);
            state.set(index, presetBits, presetBits);
        }

        void trackDeclNode(FlowState& state, AstNodeRef declRef, bool hasInitExpr)
        {
            const SemaNodeView view = sema_->viewSymbol(declRef);
            if (!view.hasSymbol())
                return;
            SmallVector<Symbol*> symbols;
            view.getSymbols(symbols);
            for (Symbol* sym : symbols)
            {
                if (sym && sym->isVariable())
                    trackDecl(state, declRef, sym->cast<SymbolVariable>(), hasInitExpr);
            }
        }

        // Registers the locals with an EXPLICIT '#null' annotation (an inferred type
        // has nothing to remove). Without an initializer the storage defaults to
        // null, which keeps the qualifier meaningful.
        void trackNullableLocals(AstNodeRef declRef, const AstVarDeclBase* varBase)
        {
            // Inside an inline/mixin expansion the declaration belongs to the callee's
            // generic code: its qualifier must stay valid across ALL instantiations.
            if (deferDepth_ || inlineDepth_ || varBase->nodeTypeRef.isInvalid())
                return;

            const SemaNodeView view = sema_->viewSymbol(declRef);
            if (!view.hasSymbol())
                return;
            SmallVector<Symbol*> symbols;
            view.getSymbols(symbols);
            for (Symbol* sym : symbols)
            {
                if (!sym || !sym->isVariable())
                    continue;
                const auto& symVar = sym->cast<SymbolVariable>();
                if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
                    symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal) ||
                    symVar.hasGlobalStorage())
                    continue;
                if (!isNullableTypeRef(symVar.typeRef()))
                    continue;
                if (nullableLocals_.size() >= 64)
                    return;

                NullableLocal local;
                local.sym = &symVar;
                if (varBase->nodeInitRef.isValid())
                {
                    local.sawValue = true;
                    local.keepNull = !valueShapeIsNonNull(varBase->nodeInitRef);
                }
                else
                {
                    local.keepNull = true; // defaults to null
                }
                nullableLocals_.push_back(local);
            }
        }

        // A value flows into a nullable local, or its address escapes.
        void noteNullableLocalWrite(AstNodeRef targetRef, AstNodeRef valueRef, bool escape)
        {
            const AstNodeRef identRef = unwrap(targetRef);
            if (identRef.isInvalid() || sema_->node(identRef).isNot(AstNodeId::Identifier))
                return;
            const int32_t index = nullableLocalIndex(identifierVariable(identRef));
            if (index < 0)
                return;
            NullableLocal& local = nullableLocals_[index];
            local.sawValue       = true;
            if (escape || valueRef.isInvalid() || !valueShapeIsNonNull(valueRef))
                local.keepNull = true;
        }

        // -------------------------------------------------------------------------

        void collectChildren(const AstNode& node, SmallVector<AstNodeRef>& out) const
        {
            Ast::nodeIdInfos(node.id()).collectChildren(out, sema_->ast(), node);
        }

        // Marks every tracked variable referenced anywhere in a subtree as escaped:
        // used for nested functions/closures whose execution point is unknown.
        void escapeSubtree(FlowState& state, AstNodeRef ref, uint32_t depth = 0)
        {
            if (ref.isInvalid() || depth > 256 || aborted_)
                return;
            ref                 = resolve(ref);
            const AstNode& node = sema_->node(ref);
            if (node.is(AstNodeId::Identifier))
            {
                const SymbolVariable* symVar = identifierVariable(ref);
                const int32_t         idx    = trackedIndex(symVar);
                if (idx >= 0)
                {
                    if (vars_[idx].defaultInitCandidate)
                        disqualifyDefaultInitElision(state, static_cast<uint32_t>(idx));
                    else
                        state.set(idx, state.getMust(idx) | (vars_[idx].fullMask & ~vars_[idx].lateMask), vars_[idx].fullMask);
                }
                const int32_t localIdx = nullableLocalIndex(symVar);
                if (localIdx >= 0)
                    nullableLocals_[localIdx].keepNull = true;
                return;
            }
            SmallVector<AstNodeRef> children;
            collectChildren(node, children);
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isValid())
                    escapeSubtree(state, childRef, depth + 1);
            }
        }

        // -------------------------------------------------------------------------

        FlowExit walk(AstNodeRef ref, FlowState& state)
        {
            if (ref.isInvalid() || aborted_)
                return FlowExit::Normal;
            if (++nodeCount_ > K_MAX_NODES)
            {
                aborted_ = true;
                return FlowExit::Normal;
            }

            // A child ref can resolve back to an ancestor through the substitution
            // table (self-substituted casts): in that case walk the RAW node instead,
            // like AstVisit's resolvesToActiveFrame guard.
            const AstNodeRef rawRef = ref;
            ref                     = resolve(ref);
            if (isActiveRef(ref))
            {
                if (ref == rawRef || isActiveRef(rawRef))
                    return FlowExit::Normal;
                ref = rawRef;
            }
            const AstNode& node = sema_->node(ref);

            // A subtree folded to a compile-time constant performs no runtime access:
            // '#typeof(v.field)', '#assert(...)' operands and friends read types, not
            // storage.
            const SemaNodeView cstView = sema_->viewConstant(ref);
            if (cstView.hasConstant() && cstView.cst())
                return FlowExit::Normal;

            // An inlined call substitutes to its expansion block, whose branches embed
            // the argument expressions at their use sites. The address of an out
            // parameter is taken AT THE CALL, unconditionally: apply the argument
            // effects on the pre-call state before walking the expansion.
            if (rawRef != ref)
            {
                const AstNode& rawNode = sema_->node(rawRef);
                if ((rawNode.is(AstNodeId::CallExpr) || rawNode.is(AstNodeId::IntrinsicCallExpr)) &&
                    node.isNot(AstNodeId::CallExpr) && node.isNot(AstNodeId::IntrinsicCallExpr))
                    applyCallArguments(rawRef, rawNode, state);
            }

            // An inline/mixin expansion is a region of its own: a 'return' inside it
            // resumes the caller's flow right after the expansion.
            const bool inlineRoot = sema_->hasInlinePayload(ref) || (rawRef != ref && sema_->hasInlinePayload(rawRef));
            if (inlineRoot)
                inlineDepth_++;

            activeRefs_.push_back(ref);
            FlowExit exit = walkDispatch(ref, node, state);
            activeRefs_.pop_back();

            if (inlineRoot)
            {
                inlineDepth_--;
                if (exit == FlowExit::Jumped)
                    exit = FlowExit::Normal;
            }
            return exit;
        }

        FlowExit walkDispatch(AstNodeRef ref, const AstNode& node, FlowState& state)
        {
            switch (node.id())
            {
                case AstNodeId::FunctionBody:
                case AstNodeId::EmbeddedBlock:
                case AstNodeId::TopLevelBlock:
                case AstNodeId::SwitchCaseBody:
                case AstNodeId::ElseStmt:
                case AstNodeId::ElseIfStmt:
                    return walkBlock(ref, node, state);

                case AstNodeId::SingleVarDecl:
                case AstNodeId::MultiVarDecl:
                {
                    // Walk the initializer first (it reads with the pre-decl state),
                    // then register the declared symbols.
                    const auto* varBase = node.is(AstNodeId::SingleVarDecl)
                                              ? static_cast<const AstVarDeclBase*>(&node.cast<AstSingleVarDecl>())
                                              : static_cast<const AstVarDeclBase*>(&node.cast<AstMultiVarDecl>());
                    if (varBase->nodeInitRef.isValid())
                        walk(varBase->nodeInitRef, state);
                    trackDeclNode(state, ref, varBase->nodeInitRef.isValid());
                    trackNullableLocals(ref, varBase);
                    return FlowExit::Normal;
                }

                case AstNodeId::VarDeclDestructuring:
                {
                    const auto& decl = node.cast<AstVarDeclDestructuring>();
                    if (decl.nodeInitRef.isValid())
                        walk(decl.nodeInitRef, state);
                    return FlowExit::Normal;
                }

                case AstNodeId::AssignStmt:
                    return walkAssign(ref, node.cast<AstAssignStmt>(), state);

                case AstNodeId::IfStmt:
                {
                    const auto& ifStmt = node.cast<AstIfStmt>();
                    walk(ifStmt.nodeConditionRef, state);
                    return walkBranches(ifStmt.nodeIfBlockRef, ifStmt.nodeElseBlockRef, state);
                }

                case AstNodeId::IfVarDecl:
                {
                    const auto& ifStmt = node.cast<AstIfVarDecl>();
                    walk(ifStmt.nodeVarRef, state);
                    walk(ifStmt.nodeWhereRef, state);
                    return walkBranches(ifStmt.nodeIfBlockRef, ifStmt.nodeElseBlockRef, state);
                }

                case AstNodeId::WhileStmt:
                {
                    const auto& whileStmt = node.cast<AstWhileStmt>();
                    walk(whileStmt.nodeExprRef, state);
                    walkLoopBody(whileStmt.nodeBodyRef, state, /*maySkip*/ true);
                    return FlowExit::Normal;
                }

                case AstNodeId::ForCStyleStmt:
                {
                    const auto& forStmt = node.cast<AstForCStyleStmt>();
                    walk(forStmt.nodeVarDeclRef, state);
                    walk(forStmt.nodeExprRef, state);
                    walkLoopBody(forStmt.nodeBodyRef, state, /*maySkip*/ true, forStmt.nodePostStmtRef);
                    return FlowExit::Normal;
                }

                case AstNodeId::ForStmt:
                case AstNodeId::ForeachStmt:
                {
                    // Same layout, distinct ids (sema retags ForStmt in place).
                    AstNodeRef exprRef, whereRef, loopBodyRef;
                    if (node.is(AstNodeId::ForStmt))
                    {
                        const auto& forStmt = node.cast<AstForStmt>();
                        exprRef             = forStmt.nodeExprRef;
                        whereRef            = forStmt.nodeWhereRef;
                        loopBodyRef         = forStmt.nodeBodyRef;
                    }
                    else
                    {
                        const auto& forStmt = node.cast<AstForeachStmt>();
                        exprRef             = forStmt.nodeExprRef;
                        whereRef            = forStmt.nodeWhereRef;
                        loopBodyRef         = forStmt.nodeBodyRef;
                    }
                    walk(exprRef, state);
                    walk(whereRef, state);
                    walkLoopBody(loopBodyRef, state, /*maySkip*/ true);
                    return FlowExit::Normal;
                }

                case AstNodeId::InfiniteLoopStmt:
                {
                    const auto& loopStmt = node.cast<AstInfiniteLoopStmt>();
                    return walkLoopBody(loopStmt.nodeBodyRef, state, /*maySkip*/ false);
                }

                case AstNodeId::SwitchStmt:
                    return walkSwitch(ref, node.cast<AstSwitchStmt>(), state);

                case AstNodeId::DeferStmt:
                {
                    // The body runs at scope exit: apply escapes only, no checks and
                    // no init recording at the textual position.
                    deferDepth_++;
                    walk(node.cast<AstDeferStmt>().nodeBodyRef, state);
                    deferDepth_--;
                    return FlowExit::Normal;
                }

                case AstNodeId::ReturnStmt:
                {
                    const auto& returnStmt = node.cast<AstReturnStmt>();
                    walk(returnStmt.nodeExprRef, state);
                    checkFullInitExit(state);
                    // A return inside an inline/mixin expansion only exits the
                    // expansion: the caller's locals are not dropped.
                    if (inlineDepth_ == 0)
                    {
                        checkDropsOnExit(state, ref, 0);
                        noteReturnValue(returnStmt.nodeExprRef);
                    }
                    return FlowExit::Jumped;
                }

                case AstNodeId::BreakStmt:
                case AstNodeId::ScopedBreakStmt:
                {
                    if (!breakables_.empty())
                    {
                        if (node.is(AstNodeId::BreakStmt))
                        {
                            BreakCtx& ctx = *breakables_.back();
                            checkDropsOnExit(state, ref, ctx.blockDepth);
                            ctx.breakStates.push_back(state);
                        }
                        else
                        {
                            // Labeled break: the target is not stored on the node, so
                            // conservatively feed every enclosing breakable.
                            checkDropsOnExit(state, ref, breakables_.front()->blockDepth);
                            for (BreakCtx* ctx : breakables_)
                                ctx->breakStates.push_back(state);
                        }
                    }
                    return FlowExit::Jumped;
                }

                case AstNodeId::ContinueStmt:
                {
                    for (const auto& breakable : std::views::reverse(breakables_))
                    {
                        if (breakable->acceptsContinue)
                        {
                            checkDropsOnExit(state, ref, breakable->blockDepth);
                            break;
                        }
                    }
                    return FlowExit::Jumped;
                }

                case AstNodeId::FallThroughStmt:
                    return FlowExit::Fell;

                case AstNodeId::UnreachableStmt:
                    return FlowExit::Jumped;

                case AstNodeId::FailExpr:
                {
                    walk(node.cast<AstFailExpr>().nodeExprRef, state);
                    if (handledDepth_ == 0)
                        checkDropsOnExit(state, ref, 0);
                    return FlowExit::Jumped;
                }

                case AstNodeId::ErrorManagementExpr:
                case AstNodeId::ErrorManagementStmt:
                {
                    const AstNodeRef innerRef = node.is(AstNodeId::ErrorManagementExpr)
                                                    ? node.cast<AstErrorManagementExpr>().nodeExprRef
                                                    : node.cast<AstErrorManagementStmt>().nodeBodyRef;
                    const TokenId    tokenId  = tokenIdOf(node, TokenId::KwdCatch);
                    if (tokenId == TokenId::KwdTry)
                    {
                        const FlowExit exit = walk(innerRef, state);
                        // The wrapped call may unwind out of the function: whatever is
                        // registered for an implicit drop must be safe to drop.
                        checkDropsOnExit(state, ref, 0);
                        return exit;
                    }
                    handledDepth_++;
                    const FlowExit exit = walk(innerRef, state);
                    handledDepth_--;
                    return exit;
                }

                case AstNodeId::CallExpr:
                case AstNodeId::IntrinsicCallExpr:
                    return walkCall(ref, node, state);

                case AstNodeId::IntrinsicInit:
                    return walkIntrinsicInit(node.cast<AstIntrinsicInit>(), state);

                case AstNodeId::IntrinsicCall:
                {
                    // 'Swag.isSet(x.f)' inspects a 'Swag.Late' field's storage: neither a
                    // read of the value nor an escape of the variable.
                    if (node.cast<AstIntrinsicCall>().intrinsicId == TokenId::IntrinsicIsSet)
                        return FlowExit::Normal;
                    return walkChildren(node, state);
                }

                case AstNodeId::Identifier:
                {
                    AccessPath path;
                    if (accessPath(ref, path))
                        checkRead(state, ref, path);
                    return FlowExit::Normal;
                }

                case AstNodeId::MemberAccessExpr:
                case AstNodeId::AutoMemberAccessExpr:
                case AstNodeId::IndexExpr:
                {
                    AccessPath path;
                    if (accessPath(ref, path))
                    {
                        checkRead(state, ref, path);
                        // Still walk index expressions for their own reads.
                        if (node.is(AstNodeId::IndexExpr))
                            walk(node.cast<AstIndexExpr>().nodeArgRef, state);
                        return FlowExit::Normal;
                    }
                    return walkChildren(node, state);
                }

                case AstNodeId::UnaryExpr:
                {
                    const auto&   unary   = node.cast<AstUnaryExpr>();
                    const TokenId tokenId = tokenIdOf(node, TokenId::SymAmpersand);
                    if (tokenId == TokenId::SymAmpersand)
                    {
                        noteNullableLocalWrite(unary.nodeExprRef, AstNodeRef::invalid(), true);
                        AccessPath path;
                        if (accessPath(unary.nodeExprRef, path))
                        {
                            markEscaped(state, ref, path);
                            return FlowExit::Normal;
                        }
                    }
                    return walkChildren(node, state);
                }

                case AstNodeId::WithStmt:
                {
                    const auto& withStmt = node.cast<AstWithStmt>();
                    walk(withStmt.nodeExprRef, state);
                    AccessPath path;
                    const bool tracked = accessPath(withStmt.nodeExprRef, path) && path.fieldIndex < 0;
                    withTargets_.push_back(tracked ? path.varIndex : -1);
                    const FlowExit exit = walk(withStmt.nodeBodyRef, state);
                    withTargets_.pop_back();
                    return exit;
                }

                case AstNodeId::WithVarDecl:
                {
                    const auto& withStmt = node.cast<AstWithVarDecl>();
                    walk(withStmt.nodeVarRef, state);
                    AccessPath path;
                    const bool tracked = accessPath(withStmt.nodeVarRef, path) && path.fieldIndex < 0;
                    withTargets_.push_back(tracked ? path.varIndex : -1);
                    const FlowExit exit = walk(withStmt.nodeBodyRef, state);
                    withTargets_.pop_back();
                    return exit;
                }

                case AstNodeId::FunctionExpr:
                case AstNodeId::ClosureExpr:
                case AstNodeId::FunctionDecl:
                {
                    // Nested function: analyzed on its own completion. Captured
                    // tracked variables escape here.
                    escapeSubtree(state, ref);
                    return FlowExit::Normal;
                }

                default:
                    return walkChildren(node, state);
            }
        }

        FlowExit walkChildren(const AstNode& node, FlowState& state)
        {
            SmallVector<AstNodeRef> children;
            collectChildren(node, children);
            auto exit = FlowExit::Normal;
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isInvalid())
                    continue;
                exit = walk(childRef, state);
                if (exit != FlowExit::Normal)
                    break;
            }
            return exit;
        }

        FlowExit walkBlock(AstNodeRef blockRef, const AstNode& node, FlowState& state)
        {
            blockDepth_++;
            const uint32_t firstVar = static_cast<uint32_t>(vars_.size());

            SmallVector<AstNodeRef> children;
            collectChildren(node, children);
            auto exit = FlowExit::Normal;
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isInvalid())
                    continue;
                exit = walk(childRef, state);
                if (exit != FlowExit::Normal)
                    break;
            }

            if (exit == FlowExit::Normal)
            {
                // Falling off the block drops the block's own droppable locals.
                for (uint32_t i = firstVar; i < vars_.size(); i++)
                {
                    if (vars_[i].blockDepth == blockDepth_)
                    {
                        checkDroppable(state, blockRef, i);
                        state.set(i, vars_[i].fullMask, vars_[i].fullMask); // out of scope: inert
                    }
                }
            }

            blockDepth_--;
            return exit;
        }

        FlowExit walkBranches(AstNodeRef thenRef, AstNodeRef elseRef, FlowState& state)
        {
            FlowState      thenState = state;
            const FlowExit thenExit  = thenRef.isValid() ? walk(thenRef, thenState) : FlowExit::Normal;

            FlowState      elseState = state;
            const FlowExit elseExit  = elseRef.isValid() ? walk(elseRef, elseState) : FlowExit::Normal;

            const bool thenFlows = thenExit == FlowExit::Normal;
            const bool elseFlows = elseExit == FlowExit::Normal;

            if (thenFlows && elseFlows)
            {
                joinInto(thenState, elseState);
                state = thenState;
                return FlowExit::Normal;
            }
            if (thenFlows)
            {
                state = thenState;
                return FlowExit::Normal;
            }
            if (elseFlows)
            {
                state = elseState;
                return FlowExit::Normal;
            }
            return FlowExit::Jumped;
        }

        FlowExit walkLoopBody(AstNodeRef bodyRef, FlowState& state, bool maySkip, AstNodeRef postRef = AstNodeRef::invalid())
        {
            BreakCtx ctx;
            ctx.acceptsContinue = true;
            ctx.blockDepth      = blockDepth_;
            breakables_.push_back(&ctx);
            loopDepth_++;

            FlowState bodyState = state;
            walk(bodyRef, bodyState);
            if (postRef.isValid())
                walk(postRef, bodyState);

            loopDepth_--;
            breakables_.pop_back();

            if (maySkip)
            {
                // Zero iterations are possible: 'must' facts stay at the entry state;
                // 'may' facts grow along any path.
                for (uint32_t i = 0; i < vars_.size(); i++)
                {
                    if (i < bodyState.may.size())
                        state.set(i, state.getMust(i), state.getMay(i) | bodyState.getMay(i));
                }
                return FlowExit::Normal;
            }

            // Infinite loop: the only way out is a break.
            if (ctx.breakStates.empty())
                return FlowExit::Jumped;
            FlowState after = ctx.breakStates[0];
            for (uint32_t i = 1; i < ctx.breakStates.size(); i++)
                joinInto(after, ctx.breakStates[i]);
            state = after;
            return FlowExit::Normal;
        }

        FlowExit walkSwitch(AstNodeRef switchRef, const AstSwitchStmt& switchStmt, FlowState& state)
        {
            walk(switchStmt.nodeExprRef, state);

            const SwitchPayload* payload    = sema_->semaPayload<SwitchPayload>(switchRef);
            bool                 exhaustive = payload && (payload->isComplete || payload->firstDefaultRef.isValid());

            BreakCtx ctx;
            ctx.acceptsContinue = false;
            ctx.blockDepth      = blockDepth_;
            breakables_.push_back(&ctx);

            SmallVector<AstNodeRef> children;
            collectChildren(switchStmt, children);

            // The sema payload does not record the default of an expressionless
            // switch: detect it structurally (a case with no match expression and no
            // 'where' guard).
            if (!exhaustive)
            {
                for (const AstNodeRef childRef : children)
                {
                    if (childRef.isInvalid())
                        continue;
                    const AstNodeRef caseRef = resolve(childRef);
                    if (sema_->node(caseRef).isNot(AstNodeId::SwitchCaseStmt))
                        continue;
                    const auto&             caseStmt = sema_->node(caseRef).cast<AstSwitchCaseStmt>();
                    SmallVector<AstNodeRef> matchExprs;
                    AstNode::collectChildren(matchExprs, sema_->ast(), caseStmt.spanExprRef);
                    if (matchExprs.empty() && caseStmt.nodeWhereRef.isInvalid())
                    {
                        exhaustive = true;
                        break;
                    }
                }
            }

            SmallVector<FlowState, 4> exitStates;
            FlowState                 fellState;
            bool                      hasFellState = false;

            for (const AstNodeRef childRef : children)
            {
                if (childRef.isInvalid())
                    continue;
                const AstNodeRef caseRef = resolve(childRef);
                if (sema_->node(caseRef).isNot(AstNodeId::SwitchCaseStmt))
                    continue;

                const auto& caseStmt = sema_->node(caseRef).cast<AstSwitchCaseStmt>();

                FlowState caseState = state;
                if (hasFellState)
                {
                    joinInto(caseState, fellState);
                    hasFellState = false;
                }

                // Case match expressions and 'where' run with the dispatch state.
                SmallVector<AstNodeRef> caseChildren;
                collectChildren(caseStmt, caseChildren);
                auto exit = FlowExit::Normal;
                for (const AstNodeRef caseChildRef : caseChildren)
                {
                    if (caseChildRef.isInvalid())
                        continue;
                    exit = walk(caseChildRef, caseState);
                    if (exit != FlowExit::Normal)
                        break;
                }

                if (exit == FlowExit::Normal)
                    exitStates.push_back(caseState);
                else if (exit == FlowExit::Fell)
                {
                    fellState    = caseState;
                    hasFellState = true;
                }
            }

            breakables_.pop_back();

            for (const FlowState& breakState : ctx.breakStates)
                exitStates.push_back(breakState);
            if (!exhaustive)
                exitStates.push_back(state);
            if (hasFellState)
                exitStates.push_back(fellState); // trailing fallthrough: treat as normal exit

            if (exitStates.empty())
                return FlowExit::Jumped;

            FlowState after = exitStates[0];
            for (uint32_t i = 1; i < exitStates.size(); i++)
                joinInto(after, exitStates[i]);
            state = after;
            return FlowExit::Normal;
        }

        FlowExit walkAssign(AstNodeRef assignRef, const AstAssignStmt& assignStmt, FlowState& state)
        {
            const TokenId tokenId = tokenIdOf(assignStmt, TokenId::SymEqual);

            // The right side reads with the pre-assignment state.
            walk(assignStmt.nodeRightRef, state);

            const AstNodeRef leftRef = resolve(assignStmt.nodeLeftRef);
            if (leftRef.isInvalid())
                return FlowExit::Normal;

            const AstNode& leftNode = sema_->node(leftRef);

            // Multi-assign / destructuring: every element is a whole definition (the
            // list lowering never drops destinations).
            if (leftNode.is(AstNodeId::AssignList))
            {
                SmallVector<AstNodeRef> elements;
                collectChildren(leftNode, elements);
                for (const AstNodeRef elementRef : elements)
                {
                    const AstNodeRef resolvedRef = resolve(elementRef);
                    if (resolvedRef.isInvalid() || sema_->node(resolvedRef).is(AstNodeId::AssignIgnore))
                        continue;
                    AccessPath path;
                    if (accessPath(resolvedRef, path))
                        markInit(state, path);
                    else
                    {
                        noteNullableLocalWrite(resolvedRef, AstNodeRef::invalid(), false);
                        walk(resolvedRef, state);
                    }
                }
                return FlowExit::Normal;
            }

            AccessPath path;
            if (!accessPath(leftRef, path))
            {
                // A whole assignment into a '#null' local feeds its contract; a
                // compound one keeps the qualifier (conservative).
                noteNullableLocalWrite(leftRef, tokenId == TokenId::SymEqual ? assignStmt.nodeRightRef : AstNodeRef::invalid(), false);

                // Not rooted at a tracked variable: ordinary reads inside the target
                // expression (indices, pointers) still need checking.
                walk(leftRef, state);
                return FlowExit::Normal;
            }

            // Index expressions on the left still read their index.
            if (leftNode.is(AstNodeId::IndexExpr))
                walk(leftNode.cast<AstIndexExpr>().nodeArgRef, state);

            // Writing THROUGH a 'Swag.Late' field ('b.item.value = x', 'b.name[i] = c')
            // dereferences the field: a read, never an initialization.
            if (path.fieldIndex >= 0 && (path.nestedField || path.indexed) &&
                (vars_[path.varIndex].lateMask & (1ull << path.fieldIndex)))
            {
                checkRead(state, assignRef, path);
                return FlowExit::Normal;
            }

            if (tokenId != TokenId::SymEqual)
            {
                // Compound assignment reads the destination first.
                checkRead(state, assignRef, path);
                return FlowExit::Normal;
            }

            if (deferDepth_)
                return FlowExit::Normal;

            TrackedVar&    var      = vars_[path.varIndex];
            const uint64_t mustBits = state.getMust(path.varIndex);
            const uint64_t mayBits  = state.getMay(path.varIndex);

            if (var.needsDefiniteInit)
            {
                if (assignStmt.modifierFlags.hasAny({AstModifierFlagsE::NoDrop, AstModifierFlagsE::Relocate}))
                {
                    markInit(state, path);
                    return FlowExit::Normal;
                }

                if (path.indexed)
                {
                    reportDefiniteInitUse(assignRef, var, path.fieldIndex);
                    state.set(path.varIndex, var.fullMask, var.fullMask);
                    return FlowExit::Normal;
                }

                // A destination drop is safe to bypass only when no path has ever
                // initialized it and this is its first loop iteration. The generated
                // assignment then carries FirstInit so codegen emits construction,
                // not replacement.
                const bool sameLoop = loopDepth_ == var.loopDepth;
                if (path.fieldIndex >= 0)
                {
                    const uint64_t fieldBit = 1ull << path.fieldIndex;
                    if (var.dropMask & fieldBit)
                    {
                        if (!(mustBits & fieldBit))
                        {
                            if (!(mayBits & fieldBit) && sameLoop)
                                sema_->ast().node(assignRef).cast<AstAssignStmt>().modifierFlags.add(AstModifierFlagsE::FirstInit);
                            else
                                reportDefiniteInitDrop(assignRef, var);
                        }
                    }
                    markInit(state, path);
                    return FlowExit::Normal;
                }

                if (var.typeHasDrop && (mustBits & var.dropMask) != var.dropMask)
                {
                    if (!(mayBits & var.dropMask) && sameLoop)
                        sema_->ast().node(assignRef).cast<AstAssignStmt>().modifierFlags.add(AstModifierFlagsE::FirstInit);
                    else
                        reportDefiniteInitDrop(assignRef, var);
                }
                markInit(state, path);
                return FlowExit::Normal;
            }

            if (!var.defaultInitCandidate)
            {
                markInit(state, path);
                return FlowExit::Normal;
            }

            // A custom setter gets the destination address. It can construct raw
            // storage only when its own body was proved to initialize every field.
            // Otherwise its contract may inspect the ordinary default before
            // replacing it, so the default remains materialized.
            if (const auto* payload = sema_->semaPayload<AssignSpecOpPayload>(assignRef);
                payload && payload->calledFn && !isFullInitializationSetter(payload->calledFn))
            {
                disqualifyDefaultInitElision(state, static_cast<uint32_t>(path.varIndex));
                return FlowExit::Normal;
            }

            if (path.indexed)
            {
                // Partial element coverage cannot prove that the aggregate default is
                // dead. The dedicated range pass handles this common case separately.
                disqualifyDefaultInitElision(state, static_cast<uint32_t>(path.varIndex));
                return FlowExit::Normal;
            }

            // The first write may bypass a destination drop only when it executes at
            // most once for this declaration. A later loop iteration has a real value.
            const bool sameLoop = loopDepth_ == var.loopDepth;
            if (path.fieldIndex >= 0)
            {
                const uint64_t fieldBit = 1ull << path.fieldIndex;
                if (!(mustBits & fieldBit))
                {
                    if ((mayBits & fieldBit) || !sameLoop)
                    {
                        disqualifyDefaultInitElision(state, static_cast<uint32_t>(path.varIndex));
                        return FlowExit::Normal;
                    }
                    var.firstInitAssignRefs.push_back(assignRef);
                }
                markInit(state, path);
                return FlowExit::Normal;
            }

            // Whole-variable assignment.
            if ((mustBits & var.fullMask) != var.fullMask)
            {
                if ((mayBits & var.fullMask) || !sameLoop)
                {
                    disqualifyDefaultInitElision(state, static_cast<uint32_t>(path.varIndex));
                    return FlowExit::Normal;
                }
                var.firstInitAssignRefs.push_back(assignRef);
            }
            markInit(state, path);
            return FlowExit::Normal;
        }

        // Applies the pre-call effects of a resolved call's arguments (escapes for
        // address-taking parameters, reads for by-value ones) plus the error-unwind
        // check. Returns false when no resolved arguments are attached.
        bool applyCallArguments(AstNodeRef callRef, const AstNode& node, FlowState& state)
        {
            SmallVector<ResolvedCallArgument> args;
            sema_->appendResolvedCallArguments(callRef, args);

            // The resolved callee, for fallible detection and parameter types.
            const SymbolFunction* calledFn = nullptr;
            {
                const SemaNodeView view = sema_->viewSymbol(callRef);
                Symbol*            sym  = view.hasSymbol() ? view.singleSymbol() : nullptr;
                if (sym && sym->isFunction())
                    calledFn = &sym->cast<SymbolFunction>();
                if (!calledFn)
                {
                    const AstNodeRef   calleeRef  = node.is(AstNodeId::CallExpr)
                                                        ? node.cast<AstCallExpr>().nodeExprRef
                                                        : node.cast<AstIntrinsicCallExpr>().nodeExprRef;
                    const SemaNodeView calleeView = sema_->viewSymbol(resolve(calleeRef));
                    Symbol*            calleeSym  = calleeView.hasSymbol() ? calleeView.singleSymbol() : nullptr;
                    if (calleeSym && calleeSym->isFunction())
                        calledFn = &calleeSym->cast<SymbolFunction>();
                }
            }

            if (!args.empty())
            {
                uint32_t paramIndex = 0;
                for (const ResolvedCallArgument& arg : args)
                {
                    const AstNodeRef argRef = unwrap(arg.argRef);
                    const uint32_t   index  = paramIndex;
                    if (arg.passKind != CallArgumentPassKind::InterfaceObject)
                        paramIndex++;

                    if (argRef.isInvalid())
                        continue;

                    // A reference-binding argument hands the local's address to the
                    // callee, which may store null through it.
                    if (arg.bindsReferenceToValue)
                        noteNullableLocalWrite(argRef, AstNodeRef::invalid(), true);

                    AccessPath path;
                    if (!accessPath(argRef, path))
                    {
                        walk(argRef, state);
                        continue;
                    }

                    // A reference-binding argument gives the callee an address.
                    bool takesAddress = arg.bindsReferenceToValue || arg.passUfcsAddressAsPointer ||
                                        arg.passKind == CallArgumentPassKind::InterfaceObject;
                    if (!takesAddress && calledFn && index < calledFn->parameters().size())
                    {
                        const SymbolVariable* param = calledFn->parameters()[index];
                        if (param && param->typeRef().isValid())
                        {
                            const TypeInfo& paramType = sema_->typeMgr().get(param->typeRef());
                            // Arrays and slices are passed by address: the callee can
                            // fill them (out-parameter shape).
                            takesAddress = paramType.isPointerOrReference() || paramType.isSlice() || paramType.isArray();
                        }
                    }

                    if (takesAddress)
                        markEscaped(state, argRef, path);
                    else
                        checkRead(state, argRef, path);
                }

                // A method callee reached through a tracked receiver ('v.method()'):
                // 'me' is passed by address.
                const AstNodeRef calleeRef         = node.is(AstNodeId::CallExpr)
                                                         ? node.cast<AstCallExpr>().nodeExprRef
                                                         : node.cast<AstIntrinsicCallExpr>().nodeExprRef;
                const AstNodeRef resolvedCalleeRef = resolve(calleeRef);
                if (resolvedCalleeRef.isValid())
                {
                    const AstNode& calleeNode = sema_->node(resolvedCalleeRef);
                    if (calleeNode.is(AstNodeId::MemberAccessExpr))
                    {
                        AccessPath path;
                        if (accessPath(calleeNode.cast<AstMemberAccessExpr>().nodeLeftRef, path))
                            markEscaped(state, calleeNode.cast<AstMemberAccessExpr>().nodeLeftRef, path);
                    }
                    else if (calleeNode.is(AstNodeId::AutoMemberAccessExpr))
                    {
                        AccessPath path;
                        if (accessPath(resolvedCalleeRef, path))
                            markEscaped(state, resolvedCalleeRef, path);
                    }
                }
            }

            // An unhandled fallible call can unwind out of the function.
            if (calledFn && calledFn->isFallible() && handledDepth_ == 0)
                checkDropsOnExit(state, callRef, 0);

            return !args.empty();
        }

        FlowExit walkCall(AstNodeRef callRef, const AstNode& node, FlowState& state)
        {
            if (!applyCallArguments(callRef, node, state))
                walkChildren(node, state);
            return FlowExit::Normal;
        }

        // 'Swag.init' is the language's explicit construction primitive. Its target
        // is storage, not a value read, and a whole local target is a complete proof
        // for a type that has no safe implicit default. In particular this keeps the
        // raw lifecycle API usable without an 'undefined' escape hatch.
        FlowExit walkIntrinsicInit(const AstIntrinsicInit& init, FlowState& state)
        {
            AstNodeRef targetRef = unwrap(init.nodeWhatRef);
            if (targetRef.isValid())
            {
                const AstNode& target = sema_->node(targetRef);
                if (target.is(AstNodeId::UnaryExpr) && tokenIdOf(target, TokenId::SymAmpersand) == TokenId::SymAmpersand)
                    targetRef = target.cast<AstUnaryExpr>().nodeExprRef;
            }

            AccessPath path;
            if (accessPath(targetRef, path) && path.fieldIndex < 0 && !path.indexed)
                markInit(state, path);
            else
                walk(init.nodeWhatRef, state);

            walk(init.nodeCountRef, state);

            SmallVector<AstNodeRef> children;
            collectChildren(init, children);
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isInvalid() || childRef == init.nodeWhatRef || childRef == init.nodeCountRef)
                    continue;
                walk(childRef, state);
            }
            return FlowExit::Normal;
        }
    };
}

namespace
{
    // The analysis needs final lifecycle facts (opDrop) for the types of the tracked
    // locals, but a function can complete before the impl blocks of those types have
    // been sema'd by their own jobs. Pre-scan the declarations and wait (pausing the
    // job) until every relevant struct is completed; the walk itself never pauses.
    Result waitTrackedTypes(Sema& sema, AstNodeRef ref, uint32_t depth)
    {
        if (ref.isInvalid() || depth > 512)
            return Result::Continue;

        const AstNodeRef resolvedRef = sema.viewZero(ref).nodeRef();
        if (resolvedRef.isValid())
            ref = resolvedRef;

        const AstNode& node = sema.node(ref);
        switch (node.id())
        {
            case AstNodeId::AssignStmt:
            {
                // Inference of a callee's complete construction is a body fact.
                // Wait for that body before this caller decides whether its first
                // assignment may use raw storage. Self-recursive setters stay
                // conservative instead of introducing a semantic wait cycle.
                const auto* payload = sema.semaPayload<AssignSpecOpPayload>(ref);
                if (payload && payload->calledFn && payload->calledFn != sema.currentFunction() &&
                    (payload->calledFn->specOpKind() == SpecOpKind::OpSet || payload->calledFn->specOpKind() == SpecOpKind::OpSetLiteral))
                    SWC_RESULT(sema.waitSemaCompleted(payload->calledFn, node.codeRef()));
                break;
            }

            case AstNodeId::FunctionExpr:
            case AstNodeId::ClosureExpr:
            case AstNodeId::FunctionDecl:
                return Result::Continue; // analyzed on their own completion

            case AstNodeId::SingleVarDecl:
            case AstNodeId::MultiVarDecl:
            {
                const AstNode& declNode    = sema.node(ref);
                const auto*    varBase     = declNode.is(AstNodeId::SingleVarDecl)
                                                 ? static_cast<const AstVarDeclBase*>(&declNode.cast<AstSingleVarDecl>())
                                                 : static_cast<const AstVarDeclBase*>(&declNode.cast<AstMultiVarDecl>());
                const bool     hasInitExpr = varBase->nodeInitRef.isValid();

                const SemaNodeView view = sema.viewSymbol(ref);
                if (!view.hasSymbol())
                    return Result::Continue;
                SmallVector<Symbol*> symbols;
                view.getSymbols(symbols);
                for (Symbol* sym : symbols)
                {
                    if (!sym || !sym->isVariable())
                        continue;
                    const auto& symVar = sym->cast<SymbolVariable>();
                    // A declaration without an initializer may have its default
                    // construction removed, so the pass needs final lifecycle facts.
                    if (hasInitExpr)
                        continue;
                    TypeRef typeRef = symVar.typeRef();
                    for (uint32_t guard = 0; guard < 8 && typeRef.isValid(); guard++)
                    {
                        const TypeInfo& type = sema.typeMgr().get(typeRef);
                        if (const TypeRef unwrapped = type.unwrap(sema.ctx(), typeRef, TypeExpandE::Alias); unwrapped.isValid() && unwrapped != typeRef)
                        {
                            typeRef = unwrapped;
                            continue;
                        }
                        if (type.isArray())
                        {
                            typeRef = type.payloadArrayElemTypeRef();
                            continue;
                        }
                        if (type.isStruct())
                            SWC_RESULT(sema.waitSemaCompleted(&type, ref));
                        break;
                    }
                }
                return Result::Continue;
            }

            default:
                break;
        }

        SmallVector<AstNodeRef> children;
        Ast::nodeIdInfos(node.id()).collectChildren(children, sema.ast(), node);
        for (const AstNodeRef childRef : children)
        {
            if (childRef.isValid() && childRef != ref)
                SWC_RESULT(waitTrackedTypes(sema, childRef, depth + 1));
        }
        return Result::Continue;
    }
}

namespace
{
    bool nullableTypeRefForCheck(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;
        if (sema.typeMgr().get(typeRef).isNullable())
            return true;
        const TypeRef unwrapped = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        return unwrapped.isValid() && sema.typeMgr().get(unwrapped).isNullable();
    }
}

bool SemaInitFlow::wantsCheck(Sema& sema, const SymbolFunction& sym)
{
    if (sema.hasInitFlowCandidates())
        return true;

    if (sym.specOpKind() == SpecOpKind::OpSet || sym.specOpKind() == SpecOpKind::OpSetLiteral)
        return true;

    if (nullableTypeRefForCheck(sema, sym.returnTypeRef()))
        return true;

    for (const SymbolVariable* param : sym.parameters())
    {
        if (param && nullableTypeRefForCheck(sema, param->typeRef()))
            return true;
    }

    return false;
}

Result SemaInitFlow::checkFunction(Sema& sema, const SymbolFunction& sym, AstNodeRef bodyRef, bool checkReturnContract)
{
    if (bodyRef.isInvalid())
        return Result::Continue;

    SWC_RESULT(waitTrackedTypes(sema, bodyRef, 0));

    Walker walker(sema, sym, checkReturnContract);
    return walker.run(bodyRef);
}

SWC_END_NAMESPACE();
