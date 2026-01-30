#include "pch.h"
#include "Sema/Symbol/Symbol.Enum.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbol.Impl.h"

SWC_BEGIN_NAMESPACE();

void SymbolEnum::addImpl(Sema& sema, SymbolImpl& symImpl)
{
    std::unique_lock lk(mutexImpls_);
    symImpl.setSymEnum(this);
    impls_.push_back(&symImpl);
    sema.ctx().compiler().notifyAlive();
}

std::vector<SymbolImpl*> SymbolEnum::impls() const
{
    std::shared_lock lk(mutexImpls_);
    return impls_;
}

void SymbolEnum::appendEnumValues(std::vector<const SymbolEnumValue*>& out) const
{
    if (const Shard* shards = shards_.load(std::memory_order_acquire))
    {
        for (uint32_t i = 0; i < SHARD_COUNT; ++i)
        {
            const Shard&     shard = shards[i];
            std::shared_lock lock(shard.mutex);
            for (const auto& it : shard.map)
            {
                for (const Symbol* cur = it.second; cur; cur = cur->nextHomonym())
                {
                    if (!cur->isIgnored() && cur->isEnumValue())
                        out.push_back(cur->safeCast<SymbolEnumValue>());
                }
            }
        }

        return;
    }

    std::shared_lock lk(mutex_);

    // Check sharded again after lock
    if (const Shard* shards = shards_.load(std::memory_order_acquire))
    {
        lk.unlock();
        for (uint32_t i = 0; i < SHARD_COUNT; ++i)
        {
            const Shard&     shard = shards[i];
            std::shared_lock lock(shard.mutex);
            for (const auto& it : shard.map)
            {
                for (const Symbol* cur = it.second; cur; cur = cur->nextHomonym())
                {
                    if (!cur->isIgnored() && cur->isEnumValue())
                        out.push_back(cur->safeCast<SymbolEnumValue>());
                }
            }
        }

        return;
    }

    if (isBig())
    {
        for (const auto& it : bigMap_)
        {
            for (const Symbol* cur = it.second; cur; cur = cur->nextHomonym())
            {
                if (!cur->isIgnored() && cur->isEnumValue())
                    out.push_back(cur->safeCast<SymbolEnumValue>());
            }
        }
    }
    else
    {
        for (uint32_t i = 0; i < smallSize_; ++i)
        {
            for (const Symbol* cur = small_[i].head; cur; cur = cur->nextHomonym())
            {
                if (!cur->isIgnored() && cur->isEnumValue())
                    out.push_back(cur->safeCast<SymbolEnumValue>());
            }
        }
    }
}

bool SymbolEnum::computeNextValue(Sema& sema, SourceViewRef srcViewRef, TokenRef tokRef)
{
    bool overflow = false;

    // Update enum "nextValue" = value << 1
    if (isEnumFlags())
    {
        if (nextValue().isZero())
        {
            const ApsInt one(1, nextValue().bitWidth(), nextValue().isUnsigned());
            nextValue().add(one, overflow);
        }
        else if (!nextValue().isPowerOf2())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_flag_enum_power_2, srcViewRef, tokRef);
            diag.addArgument(Diagnostic::ARG_VALUE, nextValue().toString());
            diag.report(sema.ctx());
            return false;
        }
        else
        {
            nextValue().shiftLeft(1, overflow);
        }
    }

    // Update enum "nextValue" = value + 1
    else
    {
        const ApsInt one(1, nextValue().bitWidth(), nextValue().isUnsigned());
        nextValue().add(one, overflow);
    }

    if (overflow)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_literal_overflow, srcViewRef, tokRef);
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, underlyingTypeRef());
        diag.report(sema.ctx());
        return false;
    }

    return true;
}

SWC_END_NAMESPACE();
