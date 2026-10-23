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

    bool nullableTypeRefForCheck(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isNullable())
            return true;

        const TypeInfo* unwrappedType = type.unwrapAliasEnumType(sema.ctx());
        return unwrappedType && unwrappedType->isNullable();
    }

    bool isFullInitializationSetter(const SymbolFunction* calledFn)
    {
        if (!calledFn)
            return false;
        if (calledFn->specOpKind() != SpecOpKind::OpSet && calledFn->specOpKind() != SpecOpKind::OpSetLiteral)
            return false;

        return calledFn->hasFullInitialization();
    }

    // Position of the entry naming 'sym' in a list of tracked variables, or -1.
    template<typename Entries>
    int32_t indexOfVariable(const Entries& entries, const SymbolVariable* sym)
    {
        if (!sym)
            return -1;

        for (uint32_t i = 0; i < entries.size(); i++)
        {
            if (entries[i].sym == sym)
                return static_cast<int32_t>(i);
        }

        return -1;
    }

    // Track safe defaults that may be elided and storage that requires proof before use.
    // Struct fields use individual bits (up to 63); other types use a single slot.
    struct TrackedVar
    {
        SymbolVariable*     sym         = nullptr;
        const SymbolStruct* fieldStruct = nullptr; // set when fields are tracked individually
        uint32_t            fieldCount  = 0;       // 0 => single slot

        uint64_t fullMask = 1;
        uint64_t dropMask = 0; // bits of fields with a drop lifecycle
        uint64_t lateMask = 0; // bits of 'late' fields ('lateOnly' tracking)

        bool typeHasDrop          = false;
        bool isRetVal             = false;
        bool lateOnly             = false; // tracked only for its 'late' fields: regular zero-initialized storage
        bool defaultInitCandidate = false;
        bool needsDefiniteInit    = false;
        bool fullInitReceiver     = false;
        bool errored              = false; // one report per variable

        SmallVector<AstNodeRef, 4> firstInitAssignRefs;

        uint32_t blockDepth = 0;
        uint32_t loopDepth  = 0;
    };

    // Per-path bitsets parallel to the tracked variables: 'must' means initialized on every
    // path and governs reads and drops; 'may' prevents drop elision if any path initialized
    // the slot. Missing entries are K_ALL_BITS because the variable is out of scope.
    struct FlowState
    {
        SmallVector<uint64_t, 8> must;
        SmallVector<uint64_t, 8> may;

        uint64_t lateGlobals = 0; // late globals proven set on every path, one bit per Walker::lateGlobals_ entry

        uint64_t getMust(uint32_t i) const { return i < must.size() ? must[i] : K_ALL_BITS; }
        uint64_t getMay(uint32_t i) const { return i < may.size() ? may[i] : K_ALL_BITS; }

        void set(uint32_t i, uint64_t mustBits, uint64_t mayBits)
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

        dst.lateGlobals &= src.lateGlobals;
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
        bool     acceptsContinue = false;
        uint32_t blockDepth      = 0;

        SmallVector<FlowState, 2> breakStates;
    };

    class Walker
    {
    public:
        Walker(Sema& sema, const SymbolFunction& sym, bool checkReturnContract) :
            sema_(&sema),
            sym_(&sym)
        {
            returnContract_ = checkReturnContract && nullableTypeRefForCheck(sema, sym.returnTypeRef());
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

                    // Every observation of storage without a safe default must follow a write.
                    // This flag also prevents codegen from materializing that impossible default.
                    if (var.needsDefiniteInit)
                    {
                        var.sym->addExtraFlag(SymbolVariableFlagsE::DefaultInitElided);
                        continue;
                    }

                    // Wait for semantic resolution to distinguish stores from user opSet calls.
                    // Omit default initialization only when every first write constructs the value.
                    if (var.defaultInitCandidate && firstInitializersCanConstruct(var))
                    {
                        var.sym->addExtraFlag(SymbolVariableFlagsE::DefaultInitElided);
                        markInitialAssignmentsAsConstruction(var);
                    }
                }
            }

            // A 'nullable' return type that no return path can produce promises a null
            // that never happens: callers pay guards for nothing.
            if (returnContract_ && returnSeen_ && !mayReturnNull_ && !aborted_)
            {
                hadError_ = true;
                auto diag = SemaError::report(*sema_, DiagnosticId::sema_err_nullable_return_contract, *sym_);
                SemaError::setReportArguments(*sema_, diag, sym_);
                diag.report(sema_->ctx());
            }

            // Reject a nullable qualifier if all incoming values are non-null and the address never escapes.
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
        Sema*                 sema_ = nullptr;
        const SymbolFunction* sym_  = nullptr;

        std::vector<TrackedVar> vars_;
        std::vector<BreakCtx*>  breakables_;
        SmallVector<int32_t, 4> withTargets_; // tracked index or -1, innermost last

        uint32_t blockDepth_   = 0;
        uint32_t loopDepth_    = 0;
        uint32_t deferDepth_   = 0;
        uint32_t handledDepth_ = 0; // catch/expect wrappers
        uint32_t inlineDepth_  = 0; // inline/mixin expansions: 'return' exits the expansion, not the function

        uint32_t conditionalDepth_ = 0; // operands that run on some paths only: and/or, ?:, orelse, Swag.assert
        uint32_t compileTimeDepth_ = 0; // compiler directives: not this function's runtime flow
        uint32_t memberNameDepth_  = 0; // the member named on the right of a member access

        uint32_t nodeCount_  = 0;
        uint32_t errorCount_ = 0;

        bool aborted_  = false;
        bool hadError_ = false;

        int32_t fullInitReceiverIndex_ = -1;

        // 'nullable' return contract tracking.
        bool returnContract_ = false;
        bool returnSeen_     = false;
        bool mayReturnNull_  = false;

        // 'nullable' local contract tracking (function-global, not path-based): a local
        // is reported when every value it can ever hold is provably non-null.
        struct NullableLocal
        {
            const SymbolVariable* sym      = nullptr;
            bool                  keepNull = false; // saw a possibly-null value or an escape
            bool                  sawValue = false;
        };

        SmallVector<NullableLocal, 8> nullableLocals_;

        // 'late' globals this function touches. Every store into one is non-null and nothing
        // clears it, so once a store completed or a read guard passed, no later read on the
        // path can observe null, whatever runs in between: these facts are never invalidated.
        struct LateGlobal
        {
            const SymbolVariable* sym = nullptr;
        };

        SmallVector<LateGlobal, 8> lateGlobals_;

        // Facts of the statement being walked. The walk does not follow the evaluation order
        // of an expression's operands, so a fact applies only from the next statement on.
        uint64_t pendingLateGlobals_ = 0;

        // An inline expansion runs inside one statement of its caller. Its own statements see
        // its own facts in order, but the caller gains them only once that statement completes,
        // joined over every 'return' that resumes after the expansion. Every node of an
        // expansion carries its payload, so the expansion opens where that payload first appears.
        struct InlineFrame
        {
            const SemaInlinePayload* payload             = nullptr;
            uint64_t                 entryLateGlobals    = 0;
            uint64_t                 outerPending        = 0;
            uint64_t                 returnedLateGlobals = K_ALL_BITS;
            bool                     returned            = false;
        };

        SmallVector<InlineFrame, 4> inlineFrames_;

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

            const AstNodeRef resolved = sema_->resolvedNodeRef(ref);
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
                        if (node.cast<AstAutoCastExpr>().modifierFlags.hasAny({AstModifierFlagsE::Try, AstModifierFlagsE::Assume}))
                            return ref;

                        ref = node.cast<AstAutoCastExpr>().nodeExprRef;
                        break;

                    case AstNodeId::CastExpr:
                        if (node.cast<AstCastExpr>().modifierFlags.hasAny({AstModifierFlagsE::Try, AstModifierFlagsE::Assume}) || node.cast<AstCastExpr>().hasFlag(AstCastExprFlagsE::Fallible))
                            return ref;

                        ref = node.cast<AstCastExpr>().nodeExprRef;
                        break;

                    case AstNodeId::AsCastExpr:
                        return ref;
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
                        const int32_t idx = indexOfVariable(vars_, identifierVariable(ref));
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

                        out.varIndex = withTargets_.empty() ? fullInitReceiverIndex_ : withTargets_.back();
                        if (out.varIndex < 0)
                            return false;

                        const auto&        autoMember = node.cast<AstAutoMemberAccessExpr>();
                        const AstNodeRef   identRef   = autoMember.nodeIdentRef.isValid() ? autoMember.nodeIdentRef : ref;
                        const SemaNodeView view       = sema_->viewSymbol(identRef);
                        const Symbol*      fieldSym   = view.hasSymbol() ? view.singleSymbol() : nullptr;

                        out.fieldIndex = fieldIndexOf(vars_[out.varIndex], fieldSym);
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

        // Reports 'id' about 'var' once, up to the error cap, naming its field when 'fieldIndex' is one.
        void reportTrackedVar(DiagnosticId id, AstNodeRef atRef, TrackedVar& var, int32_t fieldIndex)
        {
            if (deferDepth_ || aborted_ || var.errored || errorCount_ >= K_MAX_ERRORS)
                return;

            var.errored = true;
            errorCount_++;
            hadError_ = true;

            auto diag = SemaError::report(*sema_, id, atRef);
            SemaError::setReportArguments(*sema_, diag, var.sym);
            if (fieldIndex >= 0 && var.fieldStruct)
                diag.addArgument(Diagnostic::ARG_VALUE, Utf8{var.fieldStruct->fields()[fieldIndex]->name(sema_->ctx())});
            if (var.sym->codeRef().isValid() && var.sym->codeRef().srcViewRef == sema_->node(atRef).codeRef().srcViewRef)
                diag.last().addSpan(var.sym->codeRange(sema_->ctx()), "declared here");

            diag.report(sema_->ctx());
        }

        void reportLateRead(AstNodeRef atRef, TrackedVar& var, int32_t fieldIndex)
        {
            reportTrackedVar(DiagnosticId::sema_err_late_read_never_set, atRef, var, fieldIndex);
        }

        void reportDefiniteInitUse(AstNodeRef atRef, TrackedVar& var, int32_t fieldIndex)
        {
            const DiagnosticId id = fieldIndex >= 0 ? DiagnosticId::sema_err_definite_init_field_use : DiagnosticId::sema_err_definite_init_use;
            reportTrackedVar(id, atRef, var, fieldIndex);
        }

        void reportDefiniteInitDrop(AstNodeRef atRef, TrackedVar& var)
        {
            reportTrackedVar(DiagnosticId::sema_err_definite_init_drop, atRef, var, -1);
        }

        // -------------------------------------------------------------------------

        void disqualifyDefaultInitElision(FlowState& state, const uint32_t varIndex)
        {
            TrackedVar& var          = vars_[varIndex];
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
                // Whole assignment: the source's 'late' fields may legally be
                // unset, so the copy proves nothing for them.
                state.set(path.varIndex, var.fullMask & ~var.lateMask, var.fullMask);
            }
        }

        void markEscaped(FlowState& state, AstNodeRef atRef, const AccessPath& path)
        {
            TrackedVar& var = vars_[path.varIndex];
            if (var.needsDefiniteInit)
            {
                // An unknown callee may read through the address before writing to it.
                // Taking an address alone does not establish an output-parameter contract.
                checkRead(state, atRef, path);
                return;
            }

            if (var.defaultInitCandidate)
            {
                // An escaped address can expose the default value without a construction contract.
                // Keep that default materialized.
                disqualifyDefaultInitElision(state, static_cast<uint32_t>(path.varIndex));
                return;
            }

            // 'late' fields only gain 'may': the callee filling them is possible,
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

        // Pointer-like fields dereference external storage on a nested write; other fields
        // keep the write inside the tracked aggregate.
        bool writesThroughField(const TrackedVar& var, int32_t fieldIndex) const
        {
            if (fieldIndex < 0 || !var.fieldStruct)
                return false;

            const auto& fields = var.fieldStruct->fields();
            if (static_cast<size_t>(fieldIndex) >= fields.size() || !fields[fieldIndex])
                return false;

            const TypeRef fieldTypeRef = fields[fieldIndex]->typeRef();
            if (!fieldTypeRef.isValid())
                return false;

            const TypeInfo& type = sema_->typeMgr().unwrapAliasEnumTypeOrSelf(sema_->ctx(), fieldTypeRef);
            return type.isPointerOrReference();
        }

        bool isNonNullPointerLikeTypeRef(TypeRef typeRef) const
        {
            if (!typeRef.isValid())
                return false;

            const TypeInfo& declaredType = sema_->typeMgr().get(typeRef);
            if (declaredType.isNullable())
                return false;

            const TypeInfo& type = declaredType.unwrapAliasEnumTypeOrSelf(sema_->ctx());
            return !type.isNullable() && type.isPointerLikeOrReference();
        }

        // Implicit widening retypes nodes in place, so inspect the value's original shape
        // and declared types rather than its final semantic type.
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

            // 'late' field read: proven set on EVERY path elides the runtime read
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

        // The bit of a late global in FlowState::lateGlobals, or -1 for any other symbol and
        // beyond the capacity of the bitset.
        int32_t lateGlobalIndex(const SymbolVariable* symVar)
        {
            if (!symVar || !symVar->hasGlobalStorage() || !symVar->hasExtraFlag(SymbolVariableFlagsE::LateInit))
                return -1;

            const int32_t index = indexOfVariable(lateGlobals_, symVar);
            if (index >= 0)
                return index;
            if (lateGlobals_.size() >= 64)
                return -1;

            lateGlobals_.push_back({symVar});
            return static_cast<int32_t>(lateGlobals_.size() - 1);
        }

        // Only code certain to run, at runtime and in this function's own flow, proves a global set.
        bool provesLateGlobals() const
        {
            return !deferDepth_ && !handledDepth_ && !conditionalDepth_ && !compileTimeDepth_;
        }

        void commitLateGlobals(FlowState& state)
        {
            state.lateGlobals |= pendingLateGlobals_;
            pendingLateGlobals_ = 0;
        }

        // Opens a frame when 'payload' starts an expansion that is not already open.
        bool enterInlineLateGlobals(const FlowState& state, const SemaInlinePayload* payload)
        {
            if (!payload)
                return false;
            for (const InlineFrame& frame : inlineFrames_)
            {
                if (frame.payload == payload)
                    return false;
            }

            InlineFrame frame;
            frame.payload          = payload;
            frame.entryLateGlobals = state.lateGlobals;
            frame.outerPending     = pendingLateGlobals_;
            inlineFrames_.push_back(frame);
            pendingLateGlobals_ = 0;
            return true;
        }

        void returnFromInlineLateGlobals(FlowState& state)
        {
            if (inlineFrames_.empty())
                return;

            commitLateGlobals(state);
            InlineFrame& frame = inlineFrames_.back();
            frame.returnedLateGlobals &= state.lateGlobals;
            frame.returned = true;
        }

        void leaveInlineLateGlobals(FlowState& state, FlowExit exit)
        {
            commitLateGlobals(state);
            const InlineFrame frame = inlineFrames_.back();
            inlineFrames_.pop_back();

            uint64_t exitLateGlobals = state.lateGlobals;
            if (frame.returned)
                exitLateGlobals = exit == FlowExit::Normal ? exitLateGlobals & frame.returnedLateGlobals : frame.returnedLateGlobals;

            state.lateGlobals   = frame.entryLateGlobals;
            pendingLateGlobals_ = frame.outerPending | (exitLateGlobals & ~frame.entryLateGlobals);
        }

        // A late global read keeps its guard until an earlier statement proves the global set;
        // a guarded read that certainly runs proves it for the statements that follow.
        bool walkLateGlobalRead(const FlowState& state, AstNodeRef ref)
        {
            const int32_t index = lateGlobalIndex(identifierVariable(ref));
            if (index < 0)
                return false;

            // A qualified read ('Namespace.global') runs the guard of its member access, not
            // the one its name might carry: neither proves anything here.
            if (memberNameDepth_ || !SemaHelpers::hasLateReadGuard(*sema_, ref))
                return true;

            const uint64_t bit = 1ull << index;
            if (state.lateGlobals & bit)
            {
                // Compile-time code does not run where the fact holds.
                if (!compileTimeDepth_)
                    SemaHelpers::clearLateFieldReadGuard(*sema_, ref);
            }
            else if (provesLateGlobals())
            {
                pendingLateGlobals_ |= bit;
            }

            return true;
        }

        // -------------------------------------------------------------------------

        void trackFullInitReceiver(FlowState& state)
        {
            if (sym_->specOpKind() != SpecOpKind::OpSet && sym_->specOpKind() != SpecOpKind::OpSetLiteral)
                return;
            if (sym_->parameters().empty())
                return;

            SymbolVariable*     receiver = sym_->parameters().front();
            const SymbolStruct* owner    = sym_->ownerStruct();
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

            // Mixin expansions share symbols across callers: check definite initialization,
            // but do not reuse a caller's default-elision decision.
            var.defaultInitCandidate = !needsDefiniteInit && inlineDepth_ == 0;
            var.needsDefiniteInit    = needsDefiniteInit;

            uint64_t      presetBits = 0;
            const TypeRef typeRef    = symVar.typeRef();
            if (!typeRef.isValid())
                return;

            const TypeGen::LifecycleFlags lifecycle = TypeGen::lifecycleFlagsOfTypeRef(sema_->ctx(), typeRef);
            var.typeHasDrop                         = lifecycle.hasDrop;

            const TypeInfo& type        = sema_->typeMgr().get(typeRef);
            const TypeInfo& storageType = type.unwrapAliasTypeOrSelf(sema_->ctx());

            // Indexed writes need range analysis to prove full coverage. Treat arrays without
            // a safe default as one unit, initialized by whole assignment or Swag.init.
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

                uint64_t lateMask = 0;
                if (symStruct.opDrop() != nullptr)
                {
                    // The struct's own opDrop may read every field.
                    var.dropMask = var.fullMask;

                    for (uint32_t i = 0; i < var.fieldCount; i++)
                    {
                        if (symStruct.fields()[i]->hasExtraFlag(SymbolVariableFlagsE::LateInit))
                            lateMask |= 1ull << i;
                    }
                }
                else
                {
                    for (uint32_t i = 0; i < var.fieldCount; i++)
                    {
                        const SymbolVariable& field        = *symStruct.fields()[i];
                        const TypeRef         fieldTypeRef = field.typeRef();
                        if (fieldTypeRef.isValid() && TypeGen::lifecycleFlagsOfTypeRef(sema_->ctx(), fieldTypeRef).hasDrop)
                            var.dropMask |= 1ull << i;
                        if (field.hasExtraFlag(SymbolVariableFlagsE::LateInit))
                            lateMask |= 1ull << i;
                    }
                }

                if (lateMask)
                {
                    // The null sentinel of a late field is observable through a
                    // comparison with null, so it remains normally initialized.
                    var.defaultInitCandidate = false;
                    var.lateOnly             = true;
                    var.lateMask             = lateMask;
                    var.dropMask &= ~lateMask;
                    presetBits = var.fullMask & ~lateMask;
                }
            }
            else
            {
                // Register locals already receive dead-store elimination. Track them here only
                // when their type has no safe default and each observation requires proof.
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

            for (Symbol* sym : view.symbols())
            {
                if (sym && sym->isVariable())
                    trackDecl(state, declRef, sym->cast<SymbolVariable>(), hasInitExpr);
            }
        }

        // Check explicit nullable locals. Inferred types need no qualifier diagnostic,
        // and an uninitialized nullable local may still supply its null default.
        void trackNullableLocals(AstNodeRef declRef, const AstVarDeclBase* varBase)
        {
            // Generic inline expansions share the qualifier across all instantiations.
            if (deferDepth_ || inlineDepth_ || varBase->nodeTypeRef.isInvalid())
                return;

            const SemaNodeView view = sema_->viewSymbol(declRef);
            if (!view.hasSymbol())
                return;

            for (Symbol* sym : view.symbols())
            {
                if (!sym || !sym->isVariable())
                    continue;

                const auto& symVar = sym->cast<SymbolVariable>();
                if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
                    symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal) ||
                    symVar.hasGlobalStorage())
                    continue;
                if (!nullableTypeRefForCheck(*sema_, symVar.typeRef()))
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

            const int32_t index = indexOfVariable(nullableLocals_, identifierVariable(identRef));
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
        void escapeSubtree(FlowState& state, AstNodeRef ref, uint32_t depth = 0, AstNodeRef parentRef = AstNodeRef::invalid())
        {
            if (ref.isInvalid() || aborted_)
                return;

            // A subtree too deep to follow may hide an escaping capture. Give up on every
            // elision rather than conclude that nothing escaped.
            if (depth > 256)
            {
                aborted_ = true;
                return;
            }

            // An operand substituted by its own wrapper -- an implicit cast of a closure
            // argument, for one -- resolves back to that wrapper. Follow the raw operand then.
            const AstNodeRef resolvedRef = resolve(ref);
            if (resolvedRef != parentRef)
                ref = resolvedRef;

            const AstNode& node = sema_->node(ref);
            if (node.is(AstNodeId::Identifier))
            {
                const SymbolVariable* symVar = identifierVariable(ref);
                const int32_t         idx    = indexOfVariable(vars_, symVar);
                if (idx >= 0)
                {
                    if (vars_[idx].defaultInitCandidate)
                        disqualifyDefaultInitElision(state, static_cast<uint32_t>(idx));
                    else
                        state.set(idx, state.getMust(idx) | (vars_[idx].fullMask & ~vars_[idx].lateMask), vars_[idx].fullMask);
                }

                const int32_t localIdx = indexOfVariable(nullableLocals_, symVar);
                if (localIdx >= 0)
                    nullableLocals_[localIdx].keepNull = true;

                return;
            }

            SmallVector<AstNodeRef> children;
            collectChildren(node, children);

            for (const AstNodeRef childRef : children)
            {
                if (childRef.isValid())
                    escapeSubtree(state, childRef, depth + 1, ref);
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

            // Substitutions can resolve a child back to an active ancestor. Walk the raw
            // node instead, as in AstVisit's resolvesToActiveFrame guard.
            const AstNodeRef rawRef = ref;
            ref                     = resolve(ref);
            if (isActiveRef(ref))
            {
                if (ref == rawRef || isActiveRef(rawRef))
                    return FlowExit::Normal;

                ref = rawRef;
            }

            const AstNode& node = sema_->node(ref);

            // Folded constants perform no runtime access, even if their syntax names locals.
            const SemaNodeView cstView = sema_->viewConstant(ref);
            if (cstView.hasConstant() && cstView.cst())
                return FlowExit::Normal;

            // Apply argument effects before walking an inline expansion: an output argument
            // takes the address unconditionally, even when the expanded body does not use it.
            if (rawRef != ref)
            {
                const AstNode& rawNode = sema_->node(rawRef);
                if ((rawNode.is(AstNodeId::CallExpr) || rawNode.is(AstNodeId::IntrinsicCallExpr)) &&
                    node.isNot(AstNodeId::CallExpr) && node.isNot(AstNodeId::IntrinsicCallExpr))
                    applyCallArguments(rawRef, rawNode, state);
            }

            // An inline/mixin expansion is a region of its own: a 'return' inside it
            // resumes the caller's flow right after the expansion.
            const SemaInlinePayload* inlinePayload = sema_->inlinePayload(ref);
            if (!inlinePayload && rawRef != ref)
                inlinePayload = sema_->inlinePayload(rawRef);

            const bool inlineRoot = inlinePayload != nullptr;
            if (inlineRoot)
                inlineDepth_++;
            const bool lateExpansion = enterInlineLateGlobals(state, inlinePayload);

            activeRefs_.push_back(ref);
            FlowExit exit = walkDispatch(ref, node, state);
            activeRefs_.pop_back();

            if (lateExpansion)
                leaveInlineLateGlobals(state, exit);
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
                    const auto* varBase = node.is(AstNodeId::SingleVarDecl) ? static_cast<const AstVarDeclBase*>(&node.cast<AstSingleVarDecl>()) : static_cast<const AstVarDeclBase*>(&node.cast<AstMultiVarDecl>());
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

                    conditionalDepth_++;
                    walk(ifStmt.nodeWhereRef, state);
                    conditionalDepth_--;

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

                    // The filter runs once per element, and there may be none.
                    conditionalDepth_++;
                    walk(whereRef, state);
                    conditionalDepth_--;

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
                    else
                    {
                        returnFromInlineLateGlobals(state);
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
                    const AstNodeRef captureRef = node.is(AstNodeId::ErrorManagementExpr) ? node.cast<AstErrorManagementExpr>().nodeCaptureRef : node.cast<AstErrorManagementStmt>().nodeCaptureRef;
                    walk(captureRef, state);
                    const AstNodeRef innerRef = node.is(AstNodeId::ErrorManagementExpr) ? node.cast<AstErrorManagementExpr>().nodeExprRef : node.cast<AstErrorManagementStmt>().nodeBodyRef;
                    const TokenId    tokenId  = tokenIdOf(node, TokenId::KwdCatch);
                    if (tokenId == TokenId::KwdTry)
                    {
                        const FlowExit exit = walk(innerRef, state);

                        // The wrapped call may unwind out of the function: whatever is
                        // registered for an implicit drop must be safe to drop.
                        checkDropsOnExit(state, ref, 0);

                        return exit;
                    }

                    const FlowState before = state;
                    handledDepth_++;
                    const FlowExit exit = walk(innerRef, state);
                    handledDepth_--;

                    if (tokenId == TokenId::KwdCatch)
                    {
                        const AstNodeRef handlerRef = node.is(AstNodeId::ErrorManagementExpr) ? node.cast<AstErrorManagementExpr>().nodeFallbackRef : node.cast<AstErrorManagementStmt>().nodeHandlerRef;
                        FlowState        failure    = before;
                        joinInto(failure, state);
                        const FlowExit handlerExit = walk(handlerRef, failure);
                        if (handlerExit == FlowExit::Normal)
                        {
                            if (exit == FlowExit::Normal)
                                joinInto(state, failure);
                            else
                                state = std::move(failure);
                            return FlowExit::Normal;
                        }
                    }

                    return exit;
                }

                case AstNodeId::CallExpr:
                    return walkCall(ref, node, state);

                case AstNodeId::IntrinsicCallExpr:
                {
                    // An assertion evaluates nothing when assertions are off.
                    const bool isAssert = node.cast<AstIntrinsicCallExpr>().intrinsicId == TokenId::IntrinsicAssert;
                    if (isAssert)
                        conditionalDepth_++;
                    const FlowExit exit = walkCall(ref, node, state);
                    if (isAssert)
                        conditionalDepth_--;

                    return exit;
                }

                case AstNodeId::IntrinsicInit:
                    return walkIntrinsicInit(node.cast<AstIntrinsicInit>(), state);

                case AstNodeId::IntrinsicCall:
                    return walkChildren(node, state);

                case AstNodeId::RelationalExpr:
                {
                    const auto&   relational = node.cast<AstRelationalExpr>();
                    const TokenId op         = tokenIdOf(node, TokenId::Invalid);
                    if (op == TokenId::SymEqualEqual || op == TokenId::SymBangEqual)
                    {
                        // Promotion has already retyped null literals, so inspect their syntax.
                        // Comparing a late slot to literal null queries presence without reading it.
                        const bool leftIsNull  = sema_->node(relational.nodeLeftRef).is(AstNodeId::NullLiteral);
                        const bool rightIsNull = sema_->node(relational.nodeRightRef).is(AstNodeId::NullLiteral);
                        if ((leftIsNull && SemaHelpers::isLateInitAccess(*sema_, relational.nodeRightRef)) ||
                            (rightIsNull && SemaHelpers::isLateInitAccess(*sema_, relational.nodeLeftRef)))
                            return FlowExit::Normal;
                    }

                    return walkChildren(node, state);
                }

                case AstNodeId::Identifier:
                {
                    if (walkLateGlobalRead(state, ref))
                        return FlowExit::Normal;

                    AccessPath path;
                    if (accessPath(ref, path))
                        checkRead(state, ref, path);

                    return FlowExit::Normal;
                }

                case AstNodeId::LogicalExpr:
                {
                    const auto& logical = node.cast<AstLogicalExpr>();
                    walk(logical.nodeLeftRef, state);

                    conditionalDepth_++;
                    walk(logical.nodeRightRef, state);
                    conditionalDepth_--;

                    return FlowExit::Normal;
                }

                case AstNodeId::NullCoalescingExpr:
                {
                    const auto& coalescing = node.cast<AstNullCoalescingExpr>();
                    walk(coalescing.nodeLeftRef, state);

                    conditionalDepth_++;
                    walk(coalescing.nodeRightRef, state);
                    conditionalDepth_--;

                    return FlowExit::Normal;
                }

                case AstNodeId::ConditionalExpr:
                {
                    const auto& conditional = node.cast<AstConditionalExpr>();
                    walk(conditional.nodeCondRef, state);

                    conditionalDepth_++;
                    walk(conditional.nodeTrueRef, state);
                    walk(conditional.nodeFalseRef, state);
                    conditionalDepth_--;

                    return FlowExit::Normal;
                }

                case AstNodeId::OptionalChainExpr:
                {
                    conditionalDepth_++;
                    const FlowExit exit = walkChildren(node, state);
                    conditionalDepth_--;

                    return exit;
                }

                case AstNodeId::CompilerExpression:
                case AstNodeId::CompilerCall:
                case AstNodeId::CompilerCallOne:
                case AstNodeId::CompilerRunBlock:
                case AstNodeId::CompilerRunExpr:
                case AstNodeId::CompilerCodeBlock:
                case AstNodeId::CompilerCodeExpr:
                case AstNodeId::CompilerScope:
                case AstNodeId::CompilerInject:
                case AstNodeId::CompilerIf:
                case AstNodeId::CompilerSwitch:
                case AstNodeId::CompilerSwitchCase:
                {
                    compileTimeDepth_++;
                    const FlowExit exit = walkChildren(node, state);
                    compileTimeDepth_--;

                    return exit;
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

                    if (node.is(AstNodeId::MemberAccessExpr))
                    {
                        const auto& member = node.cast<AstMemberAccessExpr>();
                        walk(member.nodeLeftRef, state);

                        memberNameDepth_++;
                        walk(member.nodeRightRef, state);
                        memberNameDepth_--;

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
                    // Nested functions are analyzed separately; their captured locals escape here.
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
                commitLateGlobals(state);
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
            // The condition has run on both branches.
            commitLateGlobals(state);

            FlowState      thenState = state;
            const FlowExit thenExit  = thenRef.isValid() ? walk(thenRef, thenState) : FlowExit::Normal;
            commitLateGlobals(thenState);

            FlowState      elseState = state;
            const FlowExit elseExit  = elseRef.isValid() ? walk(elseRef, elseState) : FlowExit::Normal;
            commitLateGlobals(elseState);

            const bool thenFlows = thenExit == FlowExit::Normal;
            const bool elseFlows = elseExit == FlowExit::Normal;

            if (thenFlows && elseFlows)
            {
                joinInto(thenState, elseState);
                state = std::move(thenState);
                return FlowExit::Normal;
            }

            if (thenFlows)
            {
                state = std::move(thenState);
                return FlowExit::Normal;
            }

            if (elseFlows)
            {
                state = std::move(elseState);
                return FlowExit::Normal;
            }

            return FlowExit::Jumped;
        }

        FlowExit walkLoopBody(AstNodeRef bodyRef, FlowState& state, bool maySkip, AstNodeRef postRef = AstNodeRef::invalid())
        {
            // The loop condition has run before the first iteration and after the loop.
            commitLateGlobals(state);

            BreakCtx ctx;
            ctx.acceptsContinue = true;
            ctx.blockDepth      = blockDepth_;
            breakables_.push_back(&ctx);
            loopDepth_++;

            FlowState bodyState = state;
            walk(bodyRef, bodyState);
            if (postRef.isValid())
                walk(postRef, bodyState);
            commitLateGlobals(bodyState);

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

            FlowState& after = ctx.breakStates[0];
            for (uint32_t i = 1; i < ctx.breakStates.size(); i++)
                joinInto(after, ctx.breakStates[i]);

            state = std::move(after);
            return FlowExit::Normal;
        }

        FlowExit walkSwitch(AstNodeRef switchRef, const AstSwitchStmt& switchStmt, FlowState& state)
        {
            walk(switchStmt.nodeExprRef, state);
            commitLateGlobals(state);

            const bool exhaustive = SemaSwitch::alwaysMatchesACase(*sema_, switchRef, switchStmt);

            BreakCtx ctx;
            ctx.acceptsContinue = false;
            ctx.blockDepth      = blockDepth_;
            breakables_.push_back(&ctx);

            SmallVector<AstNodeRef> children;
            collectChildren(switchStmt, children);

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

                    // A match expression or filter runs only while no earlier one matched.
                    const bool matchPart = caseChildRef != caseStmt.nodeBodyRef;
                    if (matchPart)
                        conditionalDepth_++;
                    exit = walk(caseChildRef, caseState);
                    if (matchPart)
                        conditionalDepth_--;

                    commitLateGlobals(caseState);
                    if (exit != FlowExit::Normal)
                        break;
                }

                if (exit == FlowExit::Normal)
                    exitStates.push_back(std::move(caseState));
                else if (exit == FlowExit::Fell)
                {
                    fellState    = std::move(caseState);
                    hasFellState = true;
                }
            }

            breakables_.pop_back();

            for (FlowState& breakState : ctx.breakStates)
                exitStates.push_back(std::move(breakState));

            if (!exhaustive)
                exitStates.push_back(std::move(state));
            if (hasFellState)
                exitStates.push_back(std::move(fellState)); // trailing fallthrough: treat as normal exit

            if (exitStates.empty())
                return FlowExit::Jumped;

            FlowState& after = exitStates[0];
            for (uint32_t i = 1; i < exitStates.size(); i++)
                joinInto(after, exitStates[i]);

            state = std::move(after);
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

            // A completed store makes a late global non-null for the statements that follow.
            if (tokenId == TokenId::SymEqual && leftNode.is(AstNodeId::Identifier))
            {
                const int32_t index = lateGlobalIndex(identifierVariable(leftRef));
                if (index >= 0)
                {
                    if (provesLateGlobals())
                        pendingLateGlobals_ |= 1ull << index;
                    return FlowExit::Normal;
                }
            }

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
                // A whole assignment into a 'nullable' local feeds its contract; a
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

            // Nested or indexed writes through pointer-like fields read the field rather
            // than initialize it. Late fields also require this check: their storage holds
            // a null sentinel until the first write, even for a non-pointer field type.
            if (path.fieldIndex >= 0 && (path.nestedField || path.indexed) &&
                ((vars_[path.varIndex].lateMask & (1ull << path.fieldIndex)) ||
                 writesThroughField(vars_[path.varIndex], path.fieldIndex)))
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

                if (path.indexed || path.nestedField)
                {
                    // Partial writes cannot prove initialization of storage without a default.
                    // They are safe only after every path initialized the containing variable.
                    if ((mustBits & var.fullMask) != var.fullMask)
                        reportDefiniteInitUse(assignRef, var, path.fieldIndex);

                    state.set(path.varIndex, var.fullMask, var.fullMask);
                    return FlowExit::Normal;
                }

                // Bypass the destination drop only if no path initialized it and this is
                // its first loop iteration. FirstInit makes codegen construct the value.
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

            // A custom setter can construct raw storage only if its body initializes every
            // field. Otherwise it may inspect the ordinary default, which must remain present.
            if (const auto* payload = sema_->semaPayload<AssignSpecOpPayload>(assignRef);
                payload && payload->calledFn && !isFullInitializationSetter(payload->calledFn))
            {
                disqualifyDefaultInitElision(state, static_cast<uint32_t>(path.varIndex));
                return FlowExit::Normal;
            }

            if (path.indexed || path.nestedField)
            {
                // One element or nested member cannot prove that the aggregate default is dead.
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
                    const AstNodeRef   calleeRef  = node.is(AstNodeId::CallExpr) ? node.cast<AstCallExpr>().nodeExprRef : node.cast<AstIntrinsicCallExpr>().nodeExprRef;
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
                            takesAddress = paramType.isPointerOrReference() || paramType.isArrayOrSlice();
                        }
                    }

                    if (takesAddress)
                        markEscaped(state, argRef, path);
                    else
                        checkRead(state, argRef, path);
                }

                // A method callee reached through a tracked receiver ('v.method()'):
                // 'me' is passed by address.
                const AstNodeRef calleeRef         = node.is(AstNodeId::CallExpr) ? node.cast<AstCallExpr>().nodeExprRef : node.cast<AstIntrinsicCallExpr>().nodeExprRef;
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

        // Swag.init constructs storage without reading it. A whole local target proves
        // initialization even when its type has no safe implicit default.
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
    // Lifecycle facts may depend on impl jobs that outlive the function's semantic pass.
    // Wait for tracked structs before starting the flow walk, which must never pause.
    Result waitTrackedTypes(Sema& sema, AstNodeRef ref, uint32_t depth)
    {
        if (ref.isInvalid() || depth > 512)
            return Result::Continue;

        const AstNodeRef resolvedRef = sema.resolvedNodeRef(ref);
        if (resolvedRef.isValid())
            ref = resolvedRef;

        const AstNode& node = sema.node(ref);
        switch (node.id())
        {
            case AstNodeId::AssignStmt:
            {
                // A setter's full-construction contract depends on its completed body.
                // Skip self-recursive waits to avoid a cycle and remain conservative.
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
                const AstNode& declNode = sema.node(ref);
                const auto*    varBase  = declNode.is(AstNodeId::SingleVarDecl)
                                              ? static_cast<const AstVarDeclBase*>(&declNode.cast<AstSingleVarDecl>())
                                              : static_cast<const AstVarDeclBase*>(&declNode.cast<AstMultiVarDecl>());

                // Only declarations without an initializer can lose their default
                // construction and therefore need final lifecycle facts here.
                if (varBase->nodeInitRef.isValid())
                    return Result::Continue;

                const SemaNodeView view = sema.viewSymbol(ref);
                if (!view.hasSymbol())
                    return Result::Continue;

                for (Symbol* sym : view.symbols())
                {
                    if (!sym || !sym->isVariable())
                        continue;

                    const auto& symVar  = sym->cast<SymbolVariable>();
                    TypeRef     typeRef = symVar.typeRef();
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
