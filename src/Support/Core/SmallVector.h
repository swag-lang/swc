// ReSharper disable CppInconsistentNaming
#pragma once
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

template<class T, std::size_t InlineCapacity = 16>
class SmallVector
{
    static_assert(InlineCapacity > 0, "InlineCapacity must be > 0");
    static constexpr bool K_NOTHROW_RELOCATE = std::is_nothrow_constructible_v<T, decltype(std::move_if_noexcept(std::declval<T&>()))>;

public:
    using value_type             = T;
    using allocator_type         = std::allocator<T>;
    using size_type              = std::size_t;
    using difference_type        = std::ptrdiff_t;
    using reference              = T&;
    using const_reference        = const T&;
    using pointer                = T*;
    using const_pointer          = const T*;
    using iterator               = T*;
    using const_iterator         = const T*;
    using reverse_iterator       = std::reverse_iterator<iterator>;
    using const_reverse_iterator = std::reverse_iterator<const_iterator>;

    bool operator==(const SmallVector& other) const { return std::ranges::equal(*this, other); }

    SmallVector() noexcept :
        ptr_(inlineData())
    {
    }

    SmallVector(size_type n, const T& value) :
        SmallVector()
    {
        resize(n, value);
    }

    explicit SmallVector(size_type n) :
        SmallVector()
    {
        resize(n);
    }

    SmallVector(std::initializer_list<T> il) :
        SmallVector()
    {
        reserve(il.size());
        uninitializedCopyN(il.begin(), il.size(), ptr_);
        sizeValue_ = il.size();
    }

    SmallVector(const SmallVector& other)
        requires(std::is_copy_constructible_v<T>)
        :
        SmallVector()
    {
        alloc_ = std::allocator_traits<allocator_type>::select_on_container_copy_construction(other.alloc_);
        reserve(other.sizeValue_);
        uninitializedCopyN(other.ptr_, other.sizeValue_, ptr_);
        sizeValue_ = other.sizeValue_;
    }

    SmallVector(SmallVector&& other) noexcept(K_NOTHROW_RELOCATE) :
        ptr_(inlineData())
    {
        alloc_ = std::move(other.alloc_);
        if (other.isInline())
        {
            reserve(other.sizeValue_);
            uninitializedMoveN(other.ptr_, other.sizeValue_, ptr_);
            sizeValue_ = other.sizeValue_;
            other.clear();
        }
        else
        {
            ptr_           = other.ptr_;
            sizeValue_     = other.sizeValue_;
            capacityValue_ = other.capacityValue_;

            other.ptr_           = other.inlineData();
            other.sizeValue_     = 0;
            other.capacityValue_ = InlineCapacity;
        }
    }

    ~SmallVector()
    {
        clearHeapIfNeeded();
    }

    SmallVector& operator=(const SmallVector& other)
        requires(std::is_copy_constructible_v<T>)
    {
        if (this == &other)
            return *this;

        if constexpr (!std::allocator_traits<allocator_type>::is_always_equal::value)
        {
            if (std::allocator_traits<allocator_type>::propagate_on_container_copy_assignment::value &&
                alloc_ != other.alloc_)
            {
                clearHeapIfNeeded();
                alloc_ = other.alloc_;
            }
        }

        assign(other.begin(), other.end());
        return *this;
    }

    SmallVector& operator=(SmallVector&& other) noexcept(K_NOTHROW_RELOCATE)
    {
        if (this == &other)
            return *this;

        clearHeapIfNeeded();

        if (other.isInline())
        {
            ptr_           = inlineData();
            capacityValue_ = InlineCapacity;
            sizeValue_     = 0;
            reserve(other.sizeValue_);
            uninitializedMoveN(other.ptr_, other.sizeValue_, ptr_);
            sizeValue_ = other.sizeValue_;
            other.clear();
        }
        else
        {
            alloc_         = std::move(other.alloc_);
            ptr_           = other.ptr_;
            sizeValue_     = other.sizeValue_;
            capacityValue_ = other.capacityValue_;

            other.ptr_           = other.inlineData();
            other.sizeValue_     = 0;
            other.capacityValue_ = InlineCapacity;
        }

        return *this;
    }

    iterator       begin() noexcept { return ptr_; }
    const_iterator begin() const noexcept { return ptr_; }
    const_iterator cbegin() const noexcept { return ptr_; }

    iterator       end() noexcept { return ptr_ + sizeValue_; }
    const_iterator end() const noexcept { return ptr_ + sizeValue_; }
    const_iterator cend() const noexcept { return ptr_ + sizeValue_; }

    reverse_iterator       rbegin() noexcept { return reverse_iterator(end()); }
    const_reverse_iterator rbegin() const noexcept { return const_reverse_iterator(end()); }
    const_reverse_iterator crbegin() const noexcept { return const_reverse_iterator(end()); }
    reverse_iterator       rend() noexcept { return reverse_iterator(begin()); }
    const_reverse_iterator rend() const noexcept { return const_reverse_iterator(begin()); }
    const_reverse_iterator crend() const noexcept { return const_reverse_iterator(begin()); }

    size_type size() const noexcept { return sizeValue_; }
    uint32_t  size32() const noexcept { return static_cast<uint32_t>(sizeValue_); }
    size_type capacity() const noexcept { return capacityValue_; }
    bool      empty() const noexcept { return sizeValue_ == 0; }
    bool      isInline() const noexcept { return ptr_ == inlineData(); }

    std::span<T>       span() noexcept { return std::span<T>(ptr_, sizeValue_); }
    std::span<const T> span() const noexcept { return std::span<const T>(ptr_, sizeValue_); }

    void reserve(size_type newCapacityValue)
    {
        if (newCapacityValue <= capacityValue_)
            return;

        reallocate(growTo(newCapacityValue));
    }

    void shrink_to_fit()
    {
        if (isInline() || sizeValue_ == capacityValue_)
            return;

        if (sizeValue_ <= InlineCapacity)
        {
            T* dst = inlineData();
            uninitializedMoveN(ptr_, sizeValue_, dst);
            destroyN(ptr_, sizeValue_);
            std::allocator_traits<allocator_type>::deallocate(alloc_, ptr_, capacityValue_);
            ptr_           = dst;
            capacityValue_ = InlineCapacity;
        }
        else
        {
            reallocate(sizeValue_);
        }
    }

    T&       operator[](size_type i) noexcept { return ptr_[i]; }
    const T& operator[](size_type i) const noexcept { return ptr_[i]; }

    T& at(size_type i)
    {
        if (i >= sizeValue_)
            throw std::out_of_range("SmallVector::at");

        return ptr_[i];
    }

    const T& at(size_type i) const
    {
        if (i >= sizeValue_)
            throw std::out_of_range("SmallVector::at");

        return ptr_[i];
    }

    T&       front() { return ptr_[0]; }
    const T& front() const { return ptr_[0]; }
    T&       back() { return ptr_[sizeValue_ - 1]; }
    const T& back() const { return ptr_[sizeValue_ - 1]; }
    T*       data() noexcept { return ptr_; }
    const T* data() const noexcept { return ptr_; }

    void clear() noexcept
    {
        destroyN(ptr_, sizeValue_);
        sizeValue_ = 0;
    }

    void resize(size_type n)
    {
        if (n < sizeValue_)
        {
            destroyN(ptr_ + n, sizeValue_ - n);
            sizeValue_ = n;
        }
        else if (n > sizeValue_)
        {
            reserve(n);
            for (; sizeValue_ < n; ++sizeValue_)
                std::construct_at(ptr_ + sizeValue_);
        }
    }

    void resize(size_type n, const T& value)
    {
        if (n < sizeValue_)
        {
            destroyN(ptr_ + n, sizeValue_ - n);
            sizeValue_ = n;
        }
        else if (n > sizeValue_)
        {
            if (n > capacityValue_ && containsElementAddress(std::addressof(value)))
            {
                const T saved(value);
                resize(n, saved);
                return;
            }
            reserve(n);
            for (; sizeValue_ < n; ++sizeValue_)
                std::construct_at(ptr_ + sizeValue_, value);
        }
    }

    template<class... Args>
    T& emplace_back(Args&&... args)
    {
        if (sizeValue_ == capacityValue_)
            return growAndEmplaceBack(std::forward<Args>(args)...);
        T* p = std::construct_at(ptr_ + sizeValue_, std::forward<Args>(args)...);
        ++sizeValue_;
        return *p;
    }

    void push_back(const T& v)
    {
        emplace_back(v);
    }

    void push_back(T&& v)
    {
        emplace_back(std::move(v));
    }

    void pop_back()
    {
        SWC_ASSERT(sizeValue_ > 0);
        std::destroy_at(ptr_ + sizeValue_ - 1);
        --sizeValue_;
    }

    void append(const T* data, size_type count)
    {
        if (count == 0)
            return;

        if (sizeValue_ + count > capacityValue_ && containsElementAddress(data))
        {
            const size_type offset = static_cast<size_type>(data - ptr_);
            reserve(sizeValue_ + count);
            data = ptr_ + offset;
        }
        else
            reserve(sizeValue_ + count);
        uninitializedCopyN(data, count, ptr_ + sizeValue_);
        sizeValue_ += count;
    }

    template<class It>
    void assign(It first, It last)
    {
        clear();

        using category = std::iterator_traits<It>::iterator_category;
        assignImpl(first, last, category{});
    }

    iterator insert(const_iterator pos, const T& value)
    {
        return emplace(pos, value);
    }

    iterator insert(const_iterator pos, T&& value)
    {
        return emplace(pos, std::move(value));
    }

    template<class It>
    iterator insert(const_iterator pos, It first, It last)
    {
        using category = std::iterator_traits<It>::iterator_category;
        return insertImpl(pos, first, last, category{});
    }

    template<class... Args>
    iterator emplace(const_iterator cpos, Args&&... args)
    {
        const size_type idx = static_cast<size_type>(cpos - cbegin());
        if (idx == sizeValue_)
        {
            emplace_back(std::forward<Args>(args)...);
            return begin() + idx;
        }

        // Preserve arguments that refer to an element before growing or shifting it.
        T value(std::forward<Args>(args)...);
        if (sizeValue_ == capacityValue_)
            reallocate(growTo(sizeValue_ + 1));
        const size_type previousSize = sizeValue_;
        uninitializedMoveN(ptr_ + previousSize - 1, 1, ptr_ + previousSize);
        ++sizeValue_;
        for (size_type i = previousSize - 1; i > idx; --i)
            ptr_[i] = std::move(ptr_[i - 1]);
        ptr_[idx] = std::move(value);
        return begin() + idx;
    }

    iterator erase(const_iterator cpos)
    {
        size_type idx = static_cast<size_type>(cpos - cbegin());
        for (size_type i = idx; i + 1 < sizeValue_; ++i)
            ptr_[i] = std::move(ptr_[i + 1]);
        std::destroy_at(ptr_ + sizeValue_ - 1);
        --sizeValue_;
        return begin() + idx;
    }

    iterator erase_unordered(const_iterator cpos)
    {
        const size_type idx = static_cast<size_type>(cpos - cbegin());
        if (idx != sizeValue_ - 1)
        {
            if constexpr (K_NOTHROW_RELOCATE)
            {
                std::destroy_at(ptr_ + idx);
                std::construct_at(ptr_ + idx, std::move_if_noexcept(back()));
            }
            else if constexpr (std::is_move_assignable_v<T>)
                ptr_[idx] = std::move(back());
            else
            {
                std::destroy_at(ptr_ + idx);
                try
                {
                    std::construct_at(ptr_ + idx, std::move(back()));
                }
                catch (...)
                {
                    // No assignment can fill the hole. Retain only the live prefix.
                    destroyN(ptr_ + idx + 1, sizeValue_ - idx - 1);
                    sizeValue_ = idx;
                    throw;
                }
            }
        }
        std::destroy_at(ptr_ + sizeValue_ - 1);
        --sizeValue_;
        return begin() + idx;
    }

private:
    bool containsElementAddress(const T* element) const noexcept
    {
        const std::less<const T*> less;
        return !less(element, ptr_) && less(element, ptr_ + sizeValue_);
    }

    T* inlineData() noexcept
    {
        return std::launder(reinterpret_cast<T*>(&inlineDataStorage_[0]));
    }

    const T* inlineData() const noexcept
    {
        return std::launder(reinterpret_cast<const T*>(&inlineDataStorage_[0]));
    }

    static void destroyN(T* p, size_type n) noexcept
    {
        if constexpr (!std::is_trivially_destructible_v<T>)
        {
            for (size_type i = 0; i < n; ++i)
                std::destroy_at(p + i);
        }
    }

    static void uninitializedMoveN(T* src, size_type n, T* dst)
    {
        if constexpr (K_NOTHROW_RELOCATE)
        {
            for (size_type i = 0; i < n; ++i)
                std::construct_at(dst + i, std::move_if_noexcept(src[i]));
        }
        else if constexpr (std::is_copy_constructible_v<T>)
            std::uninitialized_copy_n(src, n, dst);
        else
            std::uninitialized_move_n(src, n, dst);
    }

    static void uninitializedCopyN(const T* src, size_type n, T* dst)
    {
        if constexpr (std::is_nothrow_copy_constructible_v<T>)
        {
            for (size_type i = 0; i < n; ++i)
                std::construct_at(dst + i, src[i]);
        }
        else
            std::uninitialized_copy_n(src, n, dst);
    }

    size_type growTo(size_type minCapacityValue) const
    {
        size_type newCapacityValue = capacityValue_ ? capacityValue_ * 2 : InlineCapacity;
        newCapacityValue           = std::max(newCapacityValue, minCapacityValue);
        return newCapacityValue;
    }

    void reallocate(size_type newCapacityValue)
    {
        T* new_mem = std::allocator_traits<allocator_type>::allocate(alloc_, newCapacityValue);
        if constexpr (K_NOTHROW_RELOCATE)
            uninitializedMoveN(ptr_, sizeValue_, new_mem);
        else
        {
            try
            {
                uninitializedMoveN(ptr_, sizeValue_, new_mem);
            }
            catch (...)
            {
                std::allocator_traits<allocator_type>::deallocate(alloc_, new_mem, newCapacityValue);
                throw;
            }
        }
        replaceStorage(new_mem, newCapacityValue);
    }

    void replaceStorage(T* newStorage, size_type newCapacityValue) noexcept
    {
        destroyN(ptr_, sizeValue_);
        if (!isInline())
            std::allocator_traits<allocator_type>::deallocate(alloc_, ptr_, capacityValue_);

        ptr_           = newStorage;
        capacityValue_ = newCapacityValue;
    }

    template<class... Args>
    T& growAndEmplaceBack(Args&&... args)
    {
        const size_type newCapacityValue = growTo(sizeValue_ + 1);
        T*              newStorage       = std::allocator_traits<allocator_type>::allocate(alloc_, newCapacityValue);
        T*              added            = newStorage + sizeValue_;
        // Construct the new value while any arguments borrowed from old elements are alive.
        if constexpr (std::is_nothrow_constructible_v<T, Args&&...> && K_NOTHROW_RELOCATE)
        {
            std::construct_at(added, std::forward<Args>(args)...);
            uninitializedMoveN(ptr_, sizeValue_, newStorage);
        }
        else
        {
            bool addedConstructed = false;
            try
            {
                std::construct_at(added, std::forward<Args>(args)...);
                addedConstructed = true;
                uninitializedMoveN(ptr_, sizeValue_, newStorage);
            }
            catch (...)
            {
                if (addedConstructed)
                    std::destroy_at(added);
                std::allocator_traits<allocator_type>::deallocate(alloc_, newStorage, newCapacityValue);
                throw;
            }
        }
        replaceStorage(newStorage, newCapacityValue);
        ++sizeValue_;
        return *added;
    }

    void clearHeapIfNeeded()
    {
        destroyN(ptr_, sizeValue_);
        if (!isInline())
        {
            std::allocator_traits<allocator_type>::deallocate(alloc_, ptr_, capacityValue_);
        }
        ptr_           = inlineData();
        sizeValue_     = 0;
        capacityValue_ = InlineCapacity;
    }

    template<class It>
    void assignImpl(It first, It last, std::input_iterator_tag)
    {
        for (; first != last; ++first)
            emplace_back(*first);
    }

    template<class It>
    void assignImpl(It first, It last, std::forward_iterator_tag)
    {
        const size_type n = static_cast<size_type>(std::distance(first, last));
        reserve(n);
        for (; first != last; ++first)
        {
            std::construct_at(ptr_ + sizeValue_, *first);
            ++sizeValue_;
        }
    }

    template<class It>
    iterator insertImpl(const_iterator cpos, It first, It last, std::input_iterator_tag)
    {
        size_type idx       = static_cast<size_type>(cpos - cbegin());
        size_type insertIdx = idx;
        for (; first != last; ++first, ++insertIdx)
            emplace(begin() + insertIdx, *first);
        return begin() + idx;
    }

    template<class It>
    iterator insertImpl(const_iterator cpos, It first, It last, std::forward_iterator_tag)
    {
        size_type idx   = static_cast<size_type>(cpos - cbegin());
        size_type count = static_cast<size_type>(std::distance(first, last));
        if (count == 0)
            return begin() + idx;

        reserve(sizeValue_ + count);

        if (idx == sizeValue_)
        {
            for (; first != last; ++first)
            {
                std::construct_at(ptr_ + sizeValue_, *first);
                ++sizeValue_;
            }
            return begin() + idx;
        }

        const size_type tail = sizeValue_ - idx;
        if (count < tail)
        {
            uninitializedMoveN(ptr_ + sizeValue_ - count, count, ptr_ + sizeValue_);
            sizeValue_ += count;
            for (size_type i = tail - count; i > 0; --i)
                ptr_[idx + count + i - 1] = std::move(ptr_[idx + i - 1]);
            for (size_type i = 0; i < count; ++i, ++first)
                ptr_[idx + i] = *first;
        }
        else
        {
            constexpr bool nothrowRange = K_NOTHROW_RELOCATE && std::is_nothrow_move_assignable_v<T> &&
                                          std::is_nothrow_constructible_v<T, decltype(*first)> && std::is_nothrow_assignable_v<T&, decltype(*first)> &&
                                          noexcept(*first) && noexcept(++first) && noexcept(first != last);
            if constexpr (!nothrowRange)
            {
                // Append a contiguous live prefix before rotating fallible values into place.
                const size_type previousSize = sizeValue_;
                for (; first != last; ++first)
                {
                    std::construct_at(ptr_ + sizeValue_, *first);
                    ++sizeValue_;
                }
                std::rotate(ptr_ + idx, ptr_ + previousSize, ptr_ + sizeValue_);
            }
            else
            {
                uninitializedMoveN(ptr_ + idx, tail, ptr_ + idx + count);
                sizeValue_ += count;
                size_type i = 0;
                for (; i < tail; ++i, ++first)
                    ptr_[idx + i] = *first;
                for (; first != last; ++first, ++i)
                    std::construct_at(ptr_ + idx + i, *first);
            }
        }

        return begin() + idx;
    }

    SWC_NO_UNIQUE_ADDRESS allocator_type alloc_{};
    T*                                   ptr_           = nullptr;
    size_type                            sizeValue_     = 0;
    size_type                            capacityValue_ = InlineCapacity;
    // Raw storage, deliberately left as it comes: every element is constructed before it is
    // read, and zeroing the buffer first made each vector pay for its whole inline capacity
    // at construction, used or not.
    alignas(T) std::byte inlineDataStorage_[sizeof(T) * InlineCapacity];
};

template<class T>
using SmallVector2 = SmallVector<T, 2>;

template<class T>
using SmallVector4 = SmallVector<T, 4>;

template<class T>
using SmallVector8 = SmallVector<T, 8>;

SWC_END_NAMESPACE();
