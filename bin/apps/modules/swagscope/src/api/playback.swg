#global public
#global namespace Viewer

using Core, Gui

// Determines what follows a file once its viewer finishes presenting it.
enum PlayMode
{
    Once        // Stops at the end of the file.
    Repeat      // Presents the same file again.
    Folder      // Continues through files of the same kind in folder order, wrapping at the end.
    Shuffle     // Continues through files of the same kind in random order, each once per round.
}

const SlideDefaultSeconds   = 5'f32                  // Initial duration of a still picture in a folder mode.
const SlideMinSeconds       = 1'f32                  // Shortest supported still-picture duration.
const SlideMaxSeconds       = 3600'f32               // Longest supported still-picture duration.
const SlideChoices: [5] f32 = [3, 5, 10, 30, 60]     // Still-picture durations offered by the playback menu, in seconds.

// Shared playback preferences, retained by the host across files and viewer instances.
struct PlaybackSettings
{
    public
    {
        mode:         PlayMode                      // Policy applied at the end of a file.
        slideSeconds: f32 = SlideDefaultSeconds     // Duration in seconds for content without an end of its own.
    }
}

// Optional host callbacks used by viewer-owned playback controls.
//
// Both callbacks borrow the document view that requests the operation and run on the GUI thread.
// They may be retained with that view. A host that omits either callback exposes a disabled menu.
struct PlaybackApi
{
    public
    {
        readSettings:  (func(*Wnd)->PlaybackSettings)?     // Reads the current shared policy for a document view.
        writeSettings: (func(*Wnd, PlaybackSettings))?     // Applies and persists the policy chosen by a document view.
    }
}

private const PlayIds:  [4] string = ["scope.play.once", "scope.play.repeat", "scope.play.folder", "scope.play.shuffle"]
private const SlideIds: [5] string = ["scope.play.slide.0", "scope.play.slide.1", "scope.play.slide.2", "scope.play.slide.3", "scope.play.slide.4"]
#assert(SlideIds.count == SlideChoices.count)

// Returns the glyph that identifies one end-of-file playback policy.
func playModeIcon(mode: PlayMode)->ThemeIcons
{
    switch #complete mode
    {
    case .Once:    return .PlayOnce
    case .Repeat:  return .RepeatOne
    case .Folder:  return .RepeatAll
    case .Shuffle: return .Shuffle
    }
}

impl PlaybackApi
{
    // Reports whether the host supports reading and changing playback preferences.
    mtd const isAvailable()->bool => .readSettings != null and .writeSettings != null

    // Reads the host policy, or returns the default policy when no reader is installed.
    mtd const settings(view: *Wnd)->PlaybackSettings
    {
        if .readSettings do
            return .readSettings!(view)
        return {}
    }

    // Appends playback modes with their icons and exclusive selection markers to a viewer-owned menu.
    //
    // `showSlideDuration` adds the duration submenu for an image viewer. The menu owns its child
    // submenu and copies the labels; its command identifiers remain valid for its entire lifetime.
    mtd const appendMenuItems(menu: *MenuCtrl, view: *Wnd, showSlideDuration = false)
    {
        let state    = .settings(view)
        let texts    = appStrings()
        let labels   = [texts.ui_PlayOnce, texts.ui_PlayRepeat, texts.ui_PlayFolder, texts.ui_PlayShuffle]
        let disabled = !.isAvailable()
        for label, index in labels
        {
            let mode = cast(PlayMode) index
            menu.addRadioItem(label, PlayIds[index], checked: state.mode == mode, disabled: disabled).icon = menu.theme().icon(playModeIcon(mode), themeRowIconSize(menu.themeMetrics()))
        }

        if showSlideDuration
        {
            menu.addSeparator()
            let slideMenu = MenuCtrl.createPopup(menu, owner: view)
            for seconds, index in SlideChoices do
                slideMenu.addRadioItem(Format.toString("% s", cast(u32) seconds).toString(), SlideIds[index], checked: state.slideSeconds == seconds, disabled: disabled)
            menu.addPopup(texts.ui_PlaySlide, slideMenu)
        }
    }

    // Applies a command produced by [[Swagscope.Viewer.PlaybackApi.appendMenuItems]] and reports whether it was handled.
    //
    // Pass the same `showSlideDuration` choice used to build the menu. Unknown commands and hosts
    // without playback callbacks return false, so a viewer can handle its other settings normally.
    mtd const applyMenuChoice(view: *Wnd, chosen: WndId, showSlideDuration = false)->bool
    {
        if !.isAvailable() do
            return false
        var state = .settings(view)
        for id, index in PlayIds where chosen == id
        {
            state.mode = cast(PlayMode) index
            .writeSettings!(view, state)
            return true
        }

        if showSlideDuration
        {
            for id, index in SlideIds where chosen == id
            {
                state.slideSeconds = SlideChoices[index]
                .writeSettings!(view, state)
                return true
            }
        }

        return false
    }
}
