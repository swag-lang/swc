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

const SlideDefaultSeconds   = 5'f32        // Initial duration of a still picture in a folder mode.
const SlideMinSeconds       = 1'f32        // Shortest supported still-picture duration.
const SlideMaxSeconds       = 3600'f32     // Longest supported still-picture duration.
const SlideChoices: [5] f32 = [3, 5, 10, 30, 60]     // Still-picture durations offered by the options, in seconds.
const VolumeStep            = 0.05'f32     // Volume change of one Up or Down key press in a media viewer.

// Shared playback preferences, retained by the host across files and viewer instances.
struct PlaybackSettings
{
    public
    {
        mode:         PlayMode     // Policy applied at the end of a file.
        slideSeconds: f32 = SlideDefaultSeconds     // Duration in seconds for content without an end of its own.
    }
}

// Optional host callbacks used by viewer-owned playback controls.
//
// Both callbacks borrow the document view that requests the operation and run on the GUI thread.
// They may be retained with that view. A host that omits either callback exposes disabled options.
struct PlaybackApi
{
    public
    {
        readSettings:  (func(*Wnd)->PlaybackSettings)?     // Reads the current shared policy for a document view.
        writeSettings: (func(*Wnd, PlaybackSettings))?     // Applies and persists the policy chosen by a document view.
    }
}

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
            return .readSettings(view)
        return {}
    }

    // Adds the play-mode link of an option sheet, and the still-picture duration with `showSlideDuration`.
    //
    // Each link opens the page of its choices; a choice writes the shared policy through the host
    // callbacks at once. Both links are disabled when the host installed no playback callbacks.
    mtd const addOptionRows(page: *OptionSheet.Page, view: *Wnd, showSlideDuration = false)
    {
        let state    = .settings(view)
        let texts    = appStrings()
        let disabled = not .isAvailable()
        let api      = me[]
        let iconSize = themeRowIconSize(view.themeMetrics())
        page.addLink(texts.ui_PlayMode,
                     playModeText(state.mode),
                     func|api, view|(modes)
                     {
                         let current = api.settings(view).mode
                         for index in 4
                         {
                             let mode = cast(PlayMode, index)
                             modes.addChoice(playModeText(mode),
                                             mode == current,
                                             func|api, view, mode|()
                                             {
                                                 var state = api.settings(view)
                                                 state.mode = mode
                                                 api.writeSettings!(view, state)
                                             },
                                             icon: view.theme().icon(playModeIcon(mode), themeRowIconSize(view.themeMetrics())))
                         }
                     },
                     icon: view.theme().icon(playModeIcon(state.mode), iconSize),
                     disabled: disabled)

        if not showSlideDuration do
            return
        page.addLink(texts.ui_PlaySlide,
                     slideText(state.slideSeconds),
                     func|api, view|(durations)
                     {
                         let current = api.settings(view).slideSeconds
                         for seconds in SlideChoices
                         {
                             durations.addChoice(slideText(seconds), seconds == current, func|api, view, seconds|()
                             {
                                 var state = api.settings(view)
                                 state.slideSeconds = seconds
                                 api.writeSettings!(view, state)
                             })
                         }
                     },
                     icon: view.theme().icon(.HourGlass, iconSize),
                     disabled: disabled)
    }
}

// Names one end-of-file playback policy in the language of the interface.
func playModeText(mode: PlayMode)->string
{
    let texts = appStrings()
    switch #complete mode
    {
    case .Once:    return texts.ui_PlayOnce
    case .Repeat:  return texts.ui_PlayRepeat
    case .Folder:  return texts.ui_PlayFolder
    case .Shuffle: return texts.ui_PlayShuffle
    }
}

// Writes a still-picture duration in whole seconds.
func slideText(seconds: f32)->String => Format.toString("% s", cast(u32, seconds))
