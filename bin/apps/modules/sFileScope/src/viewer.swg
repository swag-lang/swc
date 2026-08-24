#global internal

using Core, Gui

// Reveals `text` at its absolute byte offset without loading the preceding file content.
alias ViewerRevealMatch = func(*Wnd, u64, string)->bool

// Finds and reveals the next occurrence of `text`, wrapping once, and reports whether the
// document holds it. A viewer owning its search decides what "next" means.
alias ViewerFindText = func(*Wnd, string)->bool

// Reports whether a view is still doing work whose result has not reached the screen.
alias ViewerIsLoading = func(*Wnd)->bool

// Notifies the application that [[ViewerIsLoading]] may now answer differently.
alias ViewerReportLoadingChanged = func(*Wnd)

// Hands a decoder error discovered after creation back to the application that owns its presentation.
alias ViewerReportFailure = func(*Wnd, string)

// Hands format statistics that changed after creation back to the application status band.
alias ViewerReportDetails = func(*Wnd, string)

private func mediaWholeTimeText(total: u64)->String
{
    let hours   = total / 3_600
    let minutes = total / 60 % 60
    let rest    = total % 60
    if hours do
        return Format.toString("%:%{02}:%{02}", hours, minutes, rest)
    return Format.toString("%:%{02}", total / 60, rest)
}

// Formats a media clock as m:ss, or h:mm:ss once an hour is reached.
func mediaTimeText(seconds: f64)->String
{
    return mediaWholeTimeText(cast(u64) Math.max(Math.floor(seconds), 0))
}

// Formats a total duration, rounding a non-empty final fraction up so it never reads as zero.
func mediaDurationText(seconds: f64)->String
{
    return mediaWholeTimeText(cast(u64) Math.max(Math.ceil(seconds), 0))
}

// Formats the current and total positions of a media transport.
func mediaTimeRangeText(current, duration: f64)->String
{
    return Format.toString("% / %", mediaTimeText(current), mediaDurationText(duration))
}

// What the application asks one integrated viewer to display.
struct ViewerRequest
{
    contentParent:        *Wnd = undefined                 // Parent the document view must be created under.
    commandParent:        *Wnd = undefined                 // Parent the optional command group must be created under.
    fileName:             string                           // File the view has to show.
    reportFailure:        #null ViewerReportFailure        // Reports a decoder error discovered after creation.
    reportDetails:        #null ViewerReportDetails        // Reports format statistics that changed after creation.
    reportLoadingChanged: #null ViewerReportLoadingChanged // Re-evaluates application-owned wait feedback.
}

// What one integrated viewer gives back.
//
// A successful viewer returns `view`. When decoding stops, it leaves `view` null and returns the
// decoder's explanation through `failureReason`; the application then owns the complete error
// surface. A viewer that needs no action bar leaves `commands` null, and one that cannot reveal an
// offset leaves `revealMatch` null. A view that does no progressive work leaves `isLoading` null.
struct ViewerResult
{
    view:          #null *Wnd                  // Document view the viewer owns, or null when decoding stopped.
    commands:      #null *Wnd                  // One group of compact controls, or null.
    details:       String                      // Short format-specific summary shown by the application.
    failureReason: String                      // Decoder explanation when `view` is null, or empty on success.
    revealMatch:   #null ViewerRevealMatch     // Reveals a byte offset, or null when not searchable.
    findText:      #null ViewerFindText        // Viewer-owned search, or null to scan the file.
    isLoading:     #null ViewerIsLoading       // Reports unfinished visible work, or null for an immediate view.
}

// Creates an integrated view and reports its optional commands, details, and search callbacks.
alias ViewerCreate = func(const *ViewerRequest, *ViewerResult)
