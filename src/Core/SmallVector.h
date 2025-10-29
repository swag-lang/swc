// ReSharper disable CppInconsistentNaming
#pragma once

SWC_BEGIN_NAMESPACE()

template<class T, std::size_t InlineCapacity = 16, class Alloc = std::allocator<T>>
class SmallVector
{
    static_assert(InlineCapacity > 0, "InlineCapacity must be > 0");

public:
    using value_type      = T;
    using allocator_type  = Alloc;
    using size_type       = std::size_t;
    using difference_type = std::ptrdiff_t;
    using reference       = T&;
    using const_reference = const T&;
    using pointer         = T*;
    using const_pointer   = const T*;
    using iterator        = T*;
    using const_iterator  = const T*;

    SmallVector() noexcept(std::is_nothrow_default_constructible_v<Alloc>) :
        SmallVector(Alloc{})
    {
    }

    explicit SmallVector(const Alloc& a) noexcept :
        _alloc(a),
        _ptr(inline_data())
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
        SmallVector(std::allocator_traits<Alloc>::select_on_container_copy_construction(other._alloc))
    {
        reserve(other._size);
        uninitialized_copy_n(other._ptr, other._size, _ptr);
        _size = other._size;
    }

    SmallVector(SmallVector&& other) noexcept(std::allocator_traits<Alloc>::is_always_equal::value &&
                                              std::is_nothrow_move_constructible_v<T>) :
        _alloc(std::move(other._alloc))
    {
        if (other.is_inline())
        {
            _ptr  = inline_data();
            _cap  = InlineCapacity;
            _size = 0;
            reserve(other._size);
            uninitialized_move_n(other._ptr, other._size, _ptr);
            _size = other._size;
            other.clear();
        }
        else
        {
            _ptr        = other._ptr;
            _size       = other._size;
            _cap        = other._cap;
            other._ptr  = other.inline_data();
            other._size = 0;
            other._cap  = InlineCapacity;
        }
    }

    SmallVector& operator=(const SmallVector& other)
    {
        if (this == &other)
            return *this;
        if constexpr (!std::allocator_traits<Alloc>::is_always_equal::value)
        {
            if (std::allocator_traits<Alloc>::propagate_on_container_copy_assignment::value &&
                _alloc != other._alloc)
            {
                clear_heap_if_needed();
                _alloc = other._alloc;
            }
        }
        assign(other.begin(), other.end());
        return *this;
    }

    SmallVector& operator=(SmallVector&& other) noexcept(
    std::allocator_traits<Alloc>::is_always_equal::value && std::is_nothrow_move_constructible_v<T>)
    {
        if (this == &other)
            return *this;

        clear_heap_if_needed(); // frees heap if we own it

        if (other.is_inline())
        {
            _ptr  = inline_data();
            _cap  = InlineCapacity;
            _size = 0;
            reserve(other._size);
            uninitialized_move_n(other._ptr, other._size, _ptr);
            _size = other._size;
            other.clear();
        }
        else
        {
            _alloc      = std::move(other._alloc);
            _ptr        = other._ptr;
            _size       = other._size;
            _cap        = other._cap;
            other._ptr  = other.inline_data();
            other._size = 0;
            other._cap  = InlineCapacity;
        }
        return *this;
    }

    ~SmallVector() { clear_heap_if_needed(); }

    iterator       begin() noexcept { return _ptr; }
    const_iterator begin() const noexcept { return _ptr; }
    const_iterator cbegin() const noexcept { return _ptr; }
    iterator       end() noexcept { return _ptr + _size; }
    const_iterator end() const noexcept { return _ptr + _size; }
    const_iterator cend() const noexcept { return _ptr + _size; }

    size_type size() const noexcept { return _size; }
    size_type capacity() const noexcept { return _cap; }
    bool      empty() const noexcept { return _size == 0; }
    bool      is_inline() const noexcept { return _ptr == inline_data(); }

    void reserve(size_type new_cap)
    {
        if (new_cap <= _cap)
            return;
        reallocate(grow_to(new_cap));
    }

    void shrink_to_fit()
    {
        if (is_inline() || _size == _cap)
            return;
        if (_size <= InlineCapacity)
        {
            // move back to inline
            T* dst = inline_data();
            uninitialized_move_n(_ptr, _size, dst);
            destroy_n(_ptr, _size);
            std::allocator_traits<Alloc>::deallocate(_alloc, _ptr, _cap);
            _ptr = dst;
            _cap = InlineCapacity;
        }
        else
        {
            reallocate(_size);
        }
    }

    T&       operator[](size_type i) noexcept { return _ptr[i]; }
    const T& operator[](size_type i) const noexcept { return _ptr[i]; }

    T& at(size_type i)
    {
        if (i >= _size)
            throw std::out_of_range("small_vector::at");
        return _ptr[i];
    }
    const T& at(size_type i) const
    {
        if (i >= _size)
            throw std::out_of_range("small_vector::at");
        return _ptr[i];
    }

    T&       front() { return _ptr[0]; }
    const T& front() const { return _ptr[0]; }
    T&       back() { return _ptr[_size - 1]; }
    const T& back() const { return _ptr[_size - 1]; }

    T*       data() noexcept { return _ptr; }
    const T* data() const noexcept { return _ptr; }

    void clear() noexcept
    {
        destroy_n(_ptr, _size);
        _size = 0;
    }

    void resize(size_type n)
    {
        if (n < _size)
        {
            destroy_n(_ptr + n, _size - n);
            _size = n;
        }
        else if (n > _size)
        {
            reserve(n);
            for (; _size < n; ++_size)
                std::construct_at(_ptr + _size);
        }
    }

    void resize(size_type n, const T& value)
    {
        if (n < _size)
        {
            destroy_n(_ptr + n, _size - n);
            _size = n;
        }
        else if (n > _size)
        {
            reserve(n);
            for (; _size < n; ++_size)
                std::construct_at(_ptr + _size, value);
        }
    }

    template<class... Args>
    T& emplace_back(Args&&... args)
    {
        if (_size == _cap)
            reallocate(grow_to(_size + 1));
        T* p = std::construct_at(_ptr + _size, std::forward<Args>(args)...);
        ++_size;
        return *p;
    }

    void push_back(const T& v) { emplace_back(v); }
    void push_back(T&& v) { emplace_back(std::move(v)); }

    void pop_back()
    {
        assert(_size > 0);
        std::destroy_at(_ptr + _size - 1);
        --_size;
    }

    template<class It>
    void assign(It first, It last)
    {
        clear();
        const size_type n = static_cast<size_type>(std::distance(first, last));
        reserve(n);
        for (; first != last; ++first)
            emplace_back(*first);
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
        if (_size == _cap)
            reallocate(grow_to(_size + 1));

        if (idx == _size)
        {
            emplace_back(std::forward<Args>(args)...);
        }
        else
        {
            // make room: move-construct new last, then shift via move-assign
            std::construct_at(_ptr + _size, std::move(_ptr[_size - 1]));
            for (size_type i = _size - 1; i > idx; --i)
                _ptr[i] = std::move(_ptr[i - 1]);
            _ptr[idx].~T();
            std::construct_at(_ptr + idx, std::forward<Args>(args)...);
            ++_size;
        }
        return begin() + idx;
    }

    iterator erase(const_iterator cpos)
    {
        size_type idx = static_cast<size_type>(cpos - cbegin());
        std::destroy_at(_ptr + idx);
        for (size_type i = idx; i + 1 < _size; ++i)
            _ptr[i] = std::move(_ptr[i + 1]);
        --_size;
        return begin() + idx;
    }

    // O(1) erase, order not preserved
    iterator erase_unordered(const_iterator cpos)
    {
        size_type idx = static_cast<size_type>(cpos - cbegin());
        std::destroy_at(_ptr + idx);
        if (idx != _size - 1)
        {
            std::construct_at(_ptr + idx, std::move(back()));
            std::destroy_at(_ptr + _size - 1);
        }
        --_size;
        return begin() + idx;
    }

private:
    T* inline_data() noexcept
    {
        return std::launder(reinterpret_cast<T*>(&_inline_data[0]));
    }

    const T* inline_data() const noexcept
    {
        return std::launder(reinterpret_cast<const T*>(&_inline_data[0]));
    }

    static void destroy_n(T* p, size_type n) noexcept
    {
        for (size_type i = 0; i < n; ++i)
            std::destroy_at(p + i);
    }

    static void uninitialized_move_n(T* src, size_type n, T* dst)
    {
        size_type i = 0;
        try
        {
            for (; i < n; ++i)
                std::construct_at(dst + i, std::move_if_noexcept(src[i]));
        }
        catch (...)
        {
            destroy_n(dst, i);
            throw;
        }
    }

    static void uninitialized_copy_n(const T* src, size_type n, T* dst)
    {
        size_type i = 0;
        try
        {
            for (; i < n; ++i)
                std::construct_at(dst + i, src[i]);
        }
        catch (...)
        {
            destroy_n(dst, i);
            throw;
        }
    }

    size_type grow_to(size_type min_cap) const
    {
        size_type new_cap = _cap ? _cap * 2 : InlineCapacity;
        new_cap           = std::max(new_cap, min_cap);
        return new_cap;
    }

    void reallocate(size_type new_cap)
    {
        T* new_mem = std::allocator_traits<Alloc>::allocate(_alloc, new_cap);
        // move/copy existing into a new buffer
        uninitialized_move_n(_ptr, _size, new_mem);

        // destroy old, then free if heap
        destroy_n(_ptr, _size);
        if (!is_inline())
        {
            std::allocator_traits<Alloc>::deallocate(_alloc, _ptr, _cap);
        }

        _ptr = new_mem;
        // re-construct moved elements in place, since we destroyed them (above):
        // Actually, we already constructed at new_mem & destroyed old; _size unchanged.
        _cap = new_cap;
    }

    void clear_heap_if_needed()
    {
        destroy_n(_ptr, _size);
        if (!is_inline())
        {
            std::allocator_traits<Alloc>::deallocate(_alloc, _ptr, _cap);
        }
        _ptr  = inline_data();
        _size = 0;
        _cap  = InlineCapacity;
    }

    Alloc     _alloc{};
    T*        _ptr  = inline_data();
    size_type _size = 0;
    size_type _cap  = InlineCapacity;

    alignas(T) unsigned char _inline_data[sizeof(T) * InlineCapacity]{};
};

SWC_END_NAMESPACE()
