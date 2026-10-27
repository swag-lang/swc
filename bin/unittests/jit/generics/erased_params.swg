#global private

// 'T is Bound' is checked at each call, then erased: every call shares one instance where
// 'T' reads as its bound, so a callback is typed with the caller's struct without a cast.

struct ErasedWnd { id: s32 }
struct ErasedSlider { using wnd: ErasedWnd; progress: f32 }
struct ErasedCounter { using wnd: ErasedWnd; count: s32 }

alias ErasedUpdate = func||(*ErasedWnd, f32)

struct ErasedTrack
{
    target: *ErasedWnd?
    update: ErasedUpdate?
}

var g_ErasedTrack: ErasedTrack

func(T is ErasedWnd) erasedAnimate(target: *T, update: func||(*T, f32))
{
    g_ErasedTrack.target = target
    g_ErasedTrack.update = cast(ErasedUpdate, update)
}

func erasedStep(value: f32)
{
    g_ErasedTrack.update!(unwrap g_ErasedTrack.target, value)
}

// The shared instance sees one 'T', whatever the caller passed.
func(T is ErasedWnd) erasedName(_: *T)->string => #typeof(T).name orelse ""
func(T) plainName(_: *T)->string => #typeof(T).name orelse ""

// An erased body can forward its 'T' to another erased function.
func(T is ErasedWnd) erasedForward(target: *T, update: func||(*T, f32)) => erasedAnimate(target, update)

func(T is ErasedWnd) erasedId(target: *T)->s32 => target.id

func erasedSetCount(counter: *ErasedCounter, value: f32)
{
    counter.count = cast(s32, value)
}

var g_ErasedSlider:  ErasedSlider
var g_ErasedCounter: ErasedCounter

#test
{
    erasedAnimate(&g_ErasedSlider, func(slider, value) { slider.progress = value })
    erasedStep(0.5)
    Swag.assert(g_ErasedSlider.progress == 0.5)

    erasedForward(&g_ErasedCounter, func(counter, value) { counter.count = cast(s32, value) })
    erasedStep(3)
    Swag.assert(g_ErasedCounter.count == 3)

    erasedAnimate(&g_ErasedCounter, &erasedSetCount)
    erasedStep(7)
    Swag.assert(g_ErasedCounter.count == 7)
}

#test
{
    var slider:  ErasedSlider
    var counter: ErasedCounter
    Swag.assert(erasedName(&slider) == "T")
    Swag.assert(erasedName(&counter) == "T")
    Swag.assert(plainName(&slider) == "ErasedSlider")
    Swag.assert(plainName(&counter) == "ErasedCounter")
}

#test
{
    var slider: ErasedSlider
    slider.id = 9
    Swag.assert(erasedId(&slider) == 9)
    Swag.assert(erasedId'ErasedSlider(&slider) == 9)
    Swag.assert(erasedId(&slider.wnd) == 9)
}
