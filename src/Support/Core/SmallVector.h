// ReSharper disable CppInconsistentNaming
#pragma once

SWC_BEGIN_NAMESPACE();

template<class T, std::size_t InlineCapacity = 16, class Alloc = std::allocator<T>>
class SmallVector
{
    static_assert(InlineCapacity > 0, "InlineCapacity must be > 0");

public:
    using value_type             = T;
    using allocator_type         = Alloc;
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

    SmallVector() noexcept(std::is_nothrow_default_constructible_v<Alloc>) :
        SmallVector(Alloc{})
    {
    }

    explicit SmallVector(const Alloc& a) noexcept :
        alloc_(a),
        ptr_(inlineData())
    {
    }

    SmallVector(size_type n, const T& value, const Alloc& a = Alloc{}) :
        SmallVector(a)
    {
        resize(n, value);
    }

    explicit SmallVector(size_type n, const Alloc& a = Alloc{}) :
        SmallVector(a)
    {
        resize(n);
    }

    SmallVector(std::initializer_list<T> il, const Alloc& a = Alloc{}) :
        SmallVector(a)
    {
        reserve(il.size());
        uninitializedCopyN(il.begin(), il.size(), ptr_);
        sizeValue_ = il.size();
    }

    SmallVector(const SmallVector& other) :
        SmallVector(std::allocator_traits<Alloc>::select_on_container_copy_construction(other.alloc_))
    {
        reserve(other.sizeValue_);
        uninitializedCopyN(other.ptr_, other.sizeValue_, ptr_);
        sizeValue_ = other.sizeValue_;
    }

    SmallVector(SmallVector&& other) noexcept :
        alloc_(std::move(other.alloc_)),
        ptr_(inlineData())
    {
        if (other.isInline())
        {
            reserve(other.sizeValue_);
            uninitializedMoveN(other.ptr_, other.sizeValue_, ptr_);
            sizeValue_ = other.sizeValue_;
            other.clear();
        }
        else
        {
            ptr_                 = other.ptr_;
            sizeValue_           = other.sizeValue_;
            capacityValue_       = other.capacityValue_;
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
    {
        if (this == &other)
            return *this;

        if constexpr (!std::allocator_traits<Alloc>::is_always_equal::value)
        {
            if (std::allocator_traits<Alloc>::propagate_on_container_copy_assignment::value &&
                alloc_ != other.alloc_)
            {
                clearHeapIfNeeded();
                alloc_ = other.alloc_;
            }
        }
        assign(other.begin(), other.end());
        return *this;
    }

    SmallVector& operator=(SmallVector&& other) noexcept
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
            alloc_               = std::move(other.alloc_);
            ptr_                 = other.ptr_;
            sizeValue_           = other.sizeValue_;
            capacityValue_       = other.capacityValue_;
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

    size_type          size() const noexcept { return sizeValue_; }
    uint32_t           size32() const noexcept { return static_cast<uint32_t>(sizeValue_); }
    size_type          capacity() const noexcept { return capacityValue_; }
    bool               empty() const noexcept { return sizeValue_ == 0; }
    bool               isInline() const noexcept { return ptr_ == inlineData(); }
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
            std::allocator_traits<Alloc>::deallocate(alloc_, ptr_, capacityValue_);
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
            reserve(n);
            for (; sizeValue_ < n; ++sizeValue_)
                std::construct_at(ptr_ + sizeValue_, value);
        }
    }

    template<class... Args>
    T& emplace_back(Args&&... args)
    {
        if (sizeValue_ == capacityValue_)
            reallocate(growTo(sizeValue_ + 1));
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
        assert(sizeValue_ > 0);
        std::destroy_at(ptr_ + sizeValue_ - 1);
        --sizeValue_;
    }

    void append(const T* data, size_type count)
    {
        if (count == 0)
            return;

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
        using category = typename std::iterator_traits<It>::iterator_category;
        return insertImpl(pos, first, last, category{});
    }

    template<class... Args>
    iterator emplace(const_iterator cpos, Args&&... args)
    {
        size_type idx = static_cast<size_type>(cpos - cbegin());
        if (sizeValue_ == capacityValue_)
            reallocate(growTo(sizeValue_ + 1));

        if (idx == sizeValue_)
        {
            std::construct_at(ptr_ + sizeValue_, std::forward<Args>(args)...);
            ++sizeValue_;
        }
        else
        {
            // make room: move-construct new last, then shift via move-assign
            std::construct_at(ptr_ + sizeValue_, std::move(ptr_[sizeValue_ - 1]));
            for (size_type i = sizeValue_ - 1; i > idx; --i)
                ptr_[i] = std::move(ptr_[i - 1]);
            std::destroy_at(ptr_ + idx);
            std::construct_at(ptr_ + idx, std::forward<Args>(args)...);
            ++sizeValue_;
        }
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
        size_type idx = static_cast<size_type>(cpos - cbegin());
        std::destroy_at(ptr_ + idx);
        if (idx != sizeValue_ - 1)
        {
            std::construct_at(ptr_ + idx, std::move(back()));
            std::destroy_at(ptr_ + sizeValue_ - 1);
        }
        --sizeValue_;
        return begin() + idx;
    }

private:
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
        for (size_type i = 0; i < n; ++i)
            std::construct_at(dst + i, std::move_if_noexcept(src[i]));
    }

    static void uninitializedCopyN(const T* src, size_type n, T* dst)
    {
        for (size_type i = 0; i < n; ++i)
            std::construct_at(dst + i, src[i]);
    }

    size_type growTo(size_type minCapacityValue) const
    {
        size_type newCapacityValue = capacityValue_ ? capacityValue_ * 2 : InlineCapacity;
        newCapacityValue           = std::max(newCapacityValue, minCapacityValue);
        return newCapacityValue;
    }

    void reallocate(size_type newCapacityValue)
    {
        T* new_mem = std::allocator_traits<Alloc>::allocate(alloc_, newCapacityValue);
        uninitializedMoveN(ptr_, sizeValue_, new_mem);
        destroyN(ptr_, sizeValue_);
        if (!isInline())
            std::allocator_traits<Alloc>::deallocate(alloc_, ptr_, capacityValue_);

        ptr_           = new_mem;
        capacityValue_ = newCapacityValue;
    }

    void clearHeapIfNeeded()
    {
        destroyN(ptr_, sizeValue_);
        if (!isInline())
        {
            std::allocator_traits<Alloc>::deallocate(alloc_, ptr_, capacityValue_);
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
            emplace_back(*first);
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
                std::construct_at(ptr_ + sizeValue_++, *first);
            return begin() + idx;
        }

        const size_type tail = sizeValue_ - idx;
        if (count < tail)
        {
            uninitializedMoveN(ptr_ + sizeValue_ - count, count, ptr_ + sizeValue_);
            for (size_type i = tail - count; i > 0; --i)
                ptr_[idx + count + i - 1] = std::move(ptr_[idx + i - 1]);
            sizeValue_ += count;
            for (size_type i = 0; i < count; ++i, ++first)
                ptr_[idx + i] = *first;
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

        return begin() + idx;
    }

    Alloc     alloc_{};
    T*        ptr_           = nullptr;
    size_type sizeValue_     = 0;
    size_type capacityValue_ = InlineCapacity;
    alignas(T) std::byte inlineDataStorage_[sizeof(T) * InlineCapacity]{};
};

template<class T, class Alloc = std::allocator<T>>
using SmallVector2 = SmallVector<T, 2, Alloc>;

template<class T, class Alloc = std::allocator<T>>
using SmallVector4 = SmallVector<T, 4, Alloc>;

template<class T, class Alloc = std::allocator<T>>
using SmallVector8 = SmallVector<T, 8, Alloc>;

SWC_END_NAMESPACE();
