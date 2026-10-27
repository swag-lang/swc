#global private

/**
# Erased Type Parameters

A generic function is compiled once for every type it is called with. When its body never
needs the exact type, because it only stores pointers and hands them back, that work is
repeated for nothing. 'T is Bound' declares an erased parameter instead: each call still
deduces 'T' and checks its arguments against it, then every call shares one compiled body
where 'T' reads as 'Bound'.

The typical use is a callback that receives the object it was registered for. The caller
gets its own type in the callback, so it needs no cast, and the library keeps a single body.
*/

struct EraseWidget { visible: bool }
struct EraseSlider { using widget: EraseWidget; progress: f32 }

alias EraseUpdate = func||(*EraseWidget, f32)

struct EraseAnimation
{
    target: *EraseWidget?
    update: EraseUpdate?
}

impl EraseAnimation
{
    mtd(T is EraseWidget) start(target: *T, update: func||(*T, f32))
    {
        .target = target
        .update = cast(EraseUpdate, update)
    }

    mtd step(value: f32)
    {
        .update!(unwrap .target, value)
    }
}

var g_EraseSlider: EraseSlider

#test
{
    var animation: EraseAnimation
    animation.start(&g_EraseSlider, func(slider, value) { slider.progress = value })
    animation.step(0.25)
    Swag.assert(g_EraseSlider.progress == 0.25)
}

/**
# What the Call Checks

The single body reads every 'T' through its bound, so 'T' has to start with it: the bound is
the first field of 'T', embedded with 'using', or 'T' is the bound itself. A pointer to 'T' is
then a pointer to the bound, unchanged, and a callback typed with 'T' can be called with it.

Each argument must agree with the 'T' the call deduced. A callback that names another struct
than its target is rejected, even when both start with the bound.
*/

struct EraseCounter { using widget: EraseWidget; count: s32 }

func(T is EraseWidget) eraseShow(target: *T)->bool
{
    target.visible = true
    return target.visible
}

#test
{
    var slider:  EraseSlider
    var counter: EraseCounter
    Swag.assert(eraseShow(&slider))
    Swag.assert(eraseShow(&counter))
    Swag.assert(eraseShow(&counter.widget))
}

/**
# Inside the Body

'T' is a strict alias of its bound. Its members are the bound's members, and a pointer to 'T'
converts to a pointer to the bound. Every call sees the same 'T', which is how one body serves
them all.

The other direction is closed: a pointer to the bound, or to any other struct, does not become a
'T' inside the body, so a callback typed with 'T' only ever receives what the caller passed. A
call to another erased function proves its own 'T' by deduction, and an explicit 'cast' states
that an object is the caller's.

A callback typed with 'T' reaches storage typed with the bound only through an explicit
'cast'. That cast states the function's own contract: it calls the callback with the target it
received, never with another object.
*/

func(T is EraseWidget) eraseName(_: *T)->string => #typeof(T).name orelse ""

#test
{
    var slider:  EraseSlider
    var counter: EraseCounter
    Swag.assert(eraseName(&slider) == "T")
    Swag.assert(eraseName(&counter) == "T")
}

/**
# Across Modules

A library compiles the single instance with its own code and publishes the erased function as
a declaration of that instance. An importer deduces 'T' and checks its arguments against the
signature, then calls the library's instance: it compiles no copy of the body, and the types the
body works with stay private to the library.

A callback written for the bound itself is accepted for any 'T', since it handles every struct
that starts with the bound.
*/

func eraseHide(widget: *EraseWidget, _: f32)
{
    widget.visible = false
}

#test
{
    var animation: EraseAnimation
    var slider:    EraseSlider
    slider.visible = true
    animation.start(&slider, &eraseHide)
    animation.step(1)
    Swag.assert(not slider.visible)
}

/**
An erased parameter belongs to a function. A struct is named by its generic arguments, so it
cannot hide one: 'struct(T is Bound)' is rejected. The bound itself must be a struct.
*/
