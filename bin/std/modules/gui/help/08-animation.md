# Animation

Every [[Gui.Application]] owns one [[Gui.Animator]]. It advances finite tracks from the
application frame clock, updates only their target windows, and releases each callback when the
track completes or is cancelled. A window being hidden or destroyed cancels every track that
targets it.

Use a stable [[Gui.AnimationChannel]] for one logical property. Starting another track with the
same target and channel replaces the previous one and begins at the value currently on screen.
This makes repeated pointer input, resizing, and live theme changes retarget without a jump.

## Animate a typed value

The scheduler supports `f32`, [[Pixel.Color]], [[Math.Point]], [[Math.Vector4]], and
[[Math.Rectangle]]. The update callback says exactly which state changes; the track's
[[Gui.AnimationImpact]] says whether that state needs paint or layout.

```swag
var options: AnimationOptions
options.duration = 180'ms
options.easing   = .EaseOut

discard app.animator.animatePoint(
    panel,
    AnimationChannel.from("Example.PanelOffset"),
    {-24, 0},
    {},
    func(wnd, value) { wnd.setPresentationOffset(value); },
    options)
```

An [[Gui.AnimationHandle]] does not retain the target. Keep it only when an operation needs to
cancel or inspect that exact run. Prefer stable, descriptive channel names over global counters:
the channel is what gives retargeting its property identity.

## Coordinate tracks

An [[Gui.AnimationGroup]] starts tracks together or in insertion order. Transfer the completed
group to the scheduler with `#move`.

```swag
var group = AnimationGroup.parallel()
group.addF32(card, AnimationChannel.from("Example.CardOpacity"), 0, 1,
             func(wnd, value) { wnd.setPresentationOpacity(value); }, options)
group.addPoint(card, AnimationChannel.from("Example.CardOffset"), {16, 0}, {},
               func(wnd, value) { wnd.setPresentationOffset(value); }, options)
discard app.animator.start(#move group)
```

Use [[Gui.AnimationGroup.sequence]] for a short ordered disclosure. Springs, keyframes, and
reflection-based field mutation are deliberately outside this API: each track remains bounded,
typed, and explicit about its invalidation cost.

## Keep geometry logical

[[Gui.Wnd.presentationOpacity]], [[Gui.Wnd.presentationOffset]], and
[[Gui.Wnd.presentationClip]] affect painting for the complete window subtree. They do not change
layout, hit testing, or keyboard focus. This is the normal choice for decorative movement; call
[[Gui.Wnd.resetPresentation]] from completion when a custom transition has finished.

For a size that must participate in layout, use an `.Layout` track or
[[Gui.Animator.animateLayoutHeight]]. Layout animation is intentionally separate because it can
remeasure and arrange a larger tree on every frame.

[[Gui.Animator.transitionPage]] implements the standard restrained page arrival. A
[[Gui.Tab]] can opt into it with [[Gui.Tab.setPageTransitions]]. `gui11` is the executable example
for page transitions, parallel and sequence groups, retargeting, and reduced motion.

## Respect reduced motion

[[Gui.MotionPreference.System]] follows the Windows client-area-animation setting and refreshes
when platform settings change. Applications and tests can override it with
[[Gui.Application.setMotionPreference]]. Decorative tracks complete immediately under reduced
motion; `.Essential` tracks keep running for feedback such as indeterminate progress, without
requiring large translation or scale.

Durations and travel distances come from the motion fields in [[Gui.ThemeMetrics]], so a theme can
tune quick feedback, page changes, and layout-affecting panels as one system.

## Test exact progress

[[Gui.Testing.HeadlessHost]] defaults to reduced motion so existing widget snapshots remain at
their resting pixels. A motion test enables full motion with
[[Gui.Testing.HeadlessHost.setReducedMotion]], samples exact intervals with
[[Gui.Testing.HeadlessHost.advanceAnimations]], and can complete all remaining tracks with
[[Gui.Testing.HeadlessHost.finishAnimations]].
