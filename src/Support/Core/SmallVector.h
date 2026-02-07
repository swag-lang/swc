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
        alloc(a),
        ptr(inlineData())
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
        for (const auto& v : il)
            emplace_back(v);
    }

    SmallVector(const SmallVector& other) :
        SmallVector(std::allocator_traits<Alloc>::select_on_container_copy_construction(other.alloc))
    {
        reserve(other.sizeValue);
            uninitializedCopyN(other.ptr, other.sizeValue, ptr);
        sizeValue = other.sizeValue;
    }

    SmallVector(SmallVector&& other) noexcept :
        alloc(std::move(other.alloc)),
        ptr(inlineData())
    {
        if (other.is_inline())
        {
            reserve(other.sizeValue);
            uninitializedMoveN(other.ptr, other.sizeValue, ptr);
            sizeValue = other.sizeValue;
            other.clear();
        }
        else
        {
            ptr        = other.ptr;
            sizeValue       = other.sizeValue;
            capacityValue        = other.capacityValue;
            other.ptr  = other.inlineData();
            other.sizeValue = 0;
            other.capacityValue  = InlineCapacity;
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
                alloc != other.alloc)
            {
                clearHeapIfNeeded();
                alloc = other.alloc;
            }
        }
        assign(other.begin(), other.end());
        return *this;
    }

    SmallVector& operator=(SmallVector&& other) noexcept
    {
        if (this == &other)
            return *this;

        clearHeapIfNeeded(); // frees heap if we own it

        if (other.is_inline())
        {
            ptr  = inlineData();
            capacityValue  = InlineCapacity;
            sizeValue = 0;
            reserve(other.sizeValue);
            uninitializedMoveN(other.ptr, other.sizeValue, ptr);
            sizeValue = other.sizeValue;
            other.clear();
        }
        else
        {
            alloc      = std::move(other.alloc);
            ptr        = other.ptr;
            sizeValue       = other.sizeValue;
            capacityValue        = other.capacityValue;
            other.ptr  = other.inlineData();
            other.sizeValue = 0;
            other.capacityValue  = InlineCapacity;
        }
        return *this;
    }

    iterator       begin() noexcept { return ptr; }
    const_iterator begin() const noexcept { return ptr; }
    const_iterator cbegin() const noexcept { return ptr; }

    iterator       end() noexcept { return ptr + sizeValue; }
    const_iterator end() const noexcept { return ptr + sizeValue; }
    const_iterator cend() const noexcept { return ptr + sizeValue; }

    reverse_iterator       rbegin() noexcept { return reverse_iterator(end()); }
    const_reverse_iterator rbegin() const noexcept { return const_reverse_iterator(end()); }
    const_reverse_iterator crbegin() const noexcept { return const_reverse_iterator(end()); }
    reverse_iterator       rend() noexcept { return reverse_iterator(begin()); }
    const_reverse_iterator rend() const noexcept { return const_reverse_iterator(begin()); }
    const_reverse_iterator crend() const noexcept { return const_reverse_iterator(begin()); }

    size_type size() const noexcept { return sizeValue; }
    uint32_t  size32() const noexcept { return static_cast<uint32_t>(sizeValue); }
    size_type capacity() const noexcept { return capacityValue; }
    bool      empty() const noexcept { return sizeValue == 0; }
    bool      is_inline() const noexcept { return ptr == inlineData(); }

    // span accessors
    std::span<T> span() noexcept
    {
        return std::span<T>(ptr, sizeValue);
    }

    std::span<const T> span() const noexcept
    {
        return std::span<const T>(ptr, sizeValue);
    }

    void reserve(size_type newCapacityValue)
    {
        if (newCapacityValue <= capacityValue)
            return;
        reallocate(growTo(newCapacityValue));
    }

    void shrink_to_fit()
    {
        if (is_inline() || sizeValue == capacityValue)
            return;

        if (sizeValue <= InlineCapacity)
        {
            // move back to inline
            T* dst = inlineData();
            uninitializedMoveN(ptr, sizeValue, dst);
            destroyN(ptr, sizeValue);
            std::allocator_traits<Alloc>::deallocate(alloc, ptr, capacityValue);
            ptr = dst;
            capacityValue = InlineCapacity;
        }
        else
        {
            reallocate(sizeValue);
        }
    }

    T&       operator[](size_type i) noexcept { return ptr[i]; }
    const T& operator[](size_type i) const noexcept { return ptr[i]; }

    T& at(size_type i)
    {
        if (i >= sizeValue)
            throw std::out_of_range("SmallVector::at");
        return ptr[i];
    }

    const T& at(size_type i) const
    {
        if (i >= sizeValue)
            throw std::out_of_range("SmallVector::at");
        return ptr[i];
    }

    T&       front() { return ptr[0]; }
    const T& front() const { return ptr[0]; }

    T&       back() { return ptr[sizeValue - 1]; }
    const T& back() const { return ptr[sizeValue - 1]; }

    T*       data() noexcept { return ptr; }
    const T* data() const noexcept { return ptr; }

    void clear() noexcept
    {
        destroyN(ptr, sizeValue);
        sizeValue = 0;
    }

    void resize(size_type n)
    {
        if (n < sizeValue)
        {
            destroyN(ptr + n, sizeValue - n);
            sizeValue = n;
        }
        else if (n > sizeValue)
        {
            reserve(n);
            for (; sizeValue < n; ++sizeValue)
                std::construct_at(ptr + sizeValue);
        }
    }

    void resize(size_type n, const T& value)
    {
        if (n < sizeValue)
        {
            destroyN(ptr + n, sizeValue - n);
            sizeValue = n;
        }
        else if (n > sizeValue)
        {
            reserve(n);
            for (; sizeValue < n; ++sizeValue)
                std::construct_at(ptr + sizeValue, value);
        }
    }

    template<class... Args>
    T& emplace_back(Args&&... args)
    {
        if (sizeValue == capacityValue)
            reallocate(growTo(sizeValue + 1));
        T* p = std::construct_at(ptr + sizeValue, std::forward<Args>(args)...);
        ++sizeValue;
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
        assert(sizeValue > 0);
        std::destroy_at(ptr + sizeValue - 1);
        --sizeValue;
    }

    void append(const T* data, size_type count)
    {
        if (count == 0)
            return;

        reserve(sizeValue + count);
        uninitializedCopyN(data, count, ptr + sizeValue);
        sizeValue += count;
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

    template<class... Args>
    iterator emplace(const_iterator cpos, Args&&... args)
    {
        size_type idx = static_cast<size_type>(cpos - cbegin());
        if (sizeValue == capacityValue)
            reallocate(growTo(sizeValue + 1));

        if (idx == sizeValue)
        {
            emplace_back(std::forward<Args>(args)...);
        }
        else
        {
            // make room: move-construct new last, then shift via move-assign
            std::construct_at(ptr + sizeValue, std::move(ptr[sizeValue - 1]));
            for (size_type i = sizeValue - 1; i > idx; --i)
                ptr[i] = std::move(ptr[i - 1]);
            std::destroy_at(ptr + idx);
            std::construct_at(ptr + idx, std::forward<Args>(args)...);
            ++sizeValue;
        }
        return begin() + idx;
    }

    iterator erase(const_iterator cpos)
    {
        size_type idx = static_cast<size_type>(cpos - cbegin());
        for (size_type i = idx; i + 1 < sizeValue; ++i)
            ptr[i] = std::move(ptr[i + 1]);
        std::destroy_at(ptr + sizeValue - 1);
        --sizeValue;
        return begin() + idx;
    }

    // O(1) erase, order not preserved
    iterator erase_unordered(const_iterator cpos)
    {
        size_type idx = static_cast<size_type>(cpos - cbegin());
        std::destroy_at(ptr + idx);
        if (idx != sizeValue - 1)
        {
            std::construct_at(ptr + idx, std::move(back()));
            std::destroy_at(ptr + sizeValue - 1);
        }
        --sizeValue;
        return begin() + idx;
    }

private:
    T* inlineData() noexcept
    {
        return std::launder(reinterpret_cast<T*>(&inlineDataStorage[0]));
    }

    const T* inlineData() const noexcept
    {
        return std::launder(reinterpret_cast<const T*>(&inlineDataStorage[0]));
    }

    static void destroyN(T* p, size_type n) noexcept
    {
        for (size_type i = 0; i < n; ++i)
            std::destroy_at(p + i);
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
        size_type newCapacityValue = capacityValue ? capacityValue * 2 : InlineCapacity;
        newCapacityValue           = std::max(newCapacityValue, minCapacityValue);
        return newCapacityValue;
    }

    void reallocate(size_type newCapacityValue)
    {
        T* new_mem = std::allocator_traits<Alloc>::allocate(alloc, newCapacityValue);
        // move/copy existing into a new buffer
        uninitializedMoveN(ptr, sizeValue, new_mem);

        // destroy old, then free if heap
        destroyN(ptr, sizeValue);
        if (!is_inline())
        {
            std::allocator_traits<Alloc>::deallocate(alloc, ptr, capacityValue);
        }

        ptr = new_mem;
        capacityValue = newCapacityValue;
    }

    void clearHeapIfNeeded()
    {
        destroyN(ptr, sizeValue);
        if (!is_inline())
        {
            std::allocator_traits<Alloc>::deallocate(alloc, ptr, capacityValue);
        }
        ptr  = inlineData();
        sizeValue = 0;
        capacityValue  = InlineCapacity;
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

    Alloc     alloc{};
    T*        ptr  = nullptr;
    size_type sizeValue = 0;
    size_type capacityValue  = InlineCapacity;

    alignas(T) std::byte inlineDataStorage[sizeof(T) * InlineCapacity]{};
};

SWC_END_NAMESPACE();

