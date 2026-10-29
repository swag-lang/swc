#global public

using Core, Gui

// Visible strings of Swag Vault.
//
// The declared values are the reference English wording, and each field is one
// translatable key. Translations live in `datas/lang/<tag>/vault.tweak`; a key a
// language file omits keeps its reference value. Read the active table through
// [[appStrings]]; never keep a copy across a language switch.
struct AppStrings
{
    // Alternative phrases for command discovery; semicolons separate complete phrases.
    search_Create: string = "create vault;new container"
    search_Open:   string = "open vault;open container"

    ui_WindowTitle: string = "Swag Vault — Private virtual drives"

    // The list of vaults, and what a row says about the vault it names. The state words are
    // joined with " · " on the mono line under the name.
    ui_VaultsTitle:    string = "Vaults"
    ui_NewVault:       string = "New Vault"
    ui_OpenFile:       string = "Open a File…"
    ui_BackToVaults:   string = "← Vaults"
    ui_StateMounted:   string = "mounted on %"     // '%' is the drive the vault is mounted on.
    ui_StateLocked:    string = "locked"
    ui_StateReadWrite: string = "read and write"
    ui_StateReadOnly:  string = "read only"
    ui_StateAtStartup: string = "at startup"
    ui_StateProtected: string = "hidden volume protected"
    ui_OpenDrive:      string = "Open %"     // '%' is the drive the vault is mounted on.
    ui_Mount:          string = "Mount"
    ui_Unmount:        string = "Unmount"
    ui_Drive:          string = "Drive"
    ui_KeyFilesLink:   string = "Key Files…"
    ui_KeyFilesCount:  string = "Key Files (%)…"     // '%' is how many key files are chosen.
    ui_ReadOnly:       string = "Read Only"
    ui_ProtectHidden:  string = "Protect Hidden Volume"
    ui_MountAtStartup: string = "Mount at Startup"
    ui_Forget:         string = "Forget Vault"
    ui_ChangePassword: string = "Change Password…"
    ui_ChangeKeyFiles: string = "Change Key Files…"
    ui_Resize:         string = "Capacity and Camouflage…"
    ui_CreateHidden:   string = "Create Hidden Volume…"
    ui_StopCreating:   string = "Stop Creating"
    ui_StopResizing:   string = "Stop Resizing"
    ui_HintList:       string = "options, automatic unmounting, about"
    ui_HintPrivacy:    string = "privacy mode keeps the list empty: vaults open from here"

    // The families the lens groups the commands under.
    lens_File:    string = "File"
    lens_Vault:   string = "Vault"
    lens_Vaults:  string = "Vaults"
    lens_Privacy: string = "Privacy"
    cmd_Options:  string = "Privacy and Unmounting"

    // The page that creates a vault. Units are written in the language's own abbreviation.
    ui_CreateHelp:       string = "Choose a fixed capacity. The complete container is randomized before it is ready."
    ui_Location:         string = "Location"
    ui_Capacity:         string = "Capacity"
    ui_UnitMiB:          string = "MiB"
    ui_UnitGiB:          string = "GiB"
    ui_FreeSpace:        string = "% free on %"     // Room left on the volume of the new container: the amount, then the volume.
    ui_Password:         string = "Password"
    ui_Confirm:          string = "Confirm"
    ui_OptionalPassword: string = "Optional"
    ui_EnterAgain:       string = "Enter again"
    ui_AddKeyFilesLink:  string = "Add Key Files…"
    ui_Browse:           string = "Browse"
    ui_CreateVault:      string = "Create Encrypted Vault"

    // The page that follows a long operation.
    ui_Randomizing:   string = "Randomizing the container"
    ui_Resizing:      string = "Resizing the container"
    ui_Camouflaging:  string = "Refreshing the camouflage"
    ui_ProgressOf:    string = "% of %"     // Bytes written so far, then bytes to write.
    ui_SecondsLeft:   string = "% s left"
    ui_MinutesLeft:   string = "% min left"
    ui_RandomizeHelp: string = "Every byte is filled with noise before the vault is ready: from outside, nothing tells data from empty space."

    // The privacy and automatic-unmount page. Each option is also a lens command, so its name is
    // set the way a command is.
    ui_PrivacyTitle:         string = "Privacy"
    ui_OptionsHelp:          string = "Keep vault locations private and choose when protected drives close automatically."
    ui_PrivacyMode:          string = "Privacy Mode"
    ui_PrivacyModeHelp:      string = "Do not save container paths, browse history, or startup mounts."
    ui_UnmountOnLock:        string = "Unmount When Windows Locks"
    ui_UnmountOnLockHelp:    string = "Protected drives close as soon as the current Windows session is locked."
    ui_UnmountOnSuspend:     string = "Unmount Before Sleep"
    ui_UnmountOnSuspendHelp: string = "Protected drives close when Windows suspends the computer."
    ui_UnmountOnIdle:        string = "Unmount After Inactivity"
    ui_UnmountOnIdleHelp:    string = "Protected drives close after Windows has received no keyboard or pointer input for %."     // '%' is the delay, chosen inside the sentence.
    ui_Minutes:              string = "% minutes"

    // The boxes that change a vault. Their labels stand above the fields.
    ui_NewCapacity:          string = "New capacity"
    ui_NewPassword:          string = "New password"
    ui_ConfirmPassword:      string = "Confirm password"
    ui_ContainerPassword:    string = "Empty if the vault has none"
    ui_KeyFiles:             string = "Key files"
    ui_KeyFilesHelp:         string = "Every listed file is required. File contents are used; the files can be moved without changing access."
    ui_NoKeyFiles:           string = "No key files"
    ui_AddKeyFiles:          string = "Add Existing Key Files"
    ui_GenerateKeyFile:      string = "Create a Random Key File"
    ui_RemoveKeyFile:        string = "Remove the Selected Key File"
    ui_RemovePasswordHelp:   string = "Leave it empty to remove only the password. Any selected key files remain required."
    ui_NewCapacityHelp:      string = "Changing capacity may move used blocks that no longer fit."
    ui_KeepCapacity:         string = "Keep the current capacity"
    ui_KeepCapacityHelp:     string = "Refresh the randomized physical size without moving vault data."
    ui_HiddenPassword:       string = "Hidden volume password"
    ui_HiddenCreateHelp:     string = "Uses contiguous free space in this vault. Replaces any previous hidden volume. Outer writes can destroy it unless protection is enabled at each mount."
    ui_HiddenProtectionHelp: string = "Enter the hidden access to protect its space. A conflicting write stops all further writes until unmount. The hidden drive is not mounted."
    ui_OuterReserve:         string = "Keep free for the outer volume"
    ui_OuterReserveHelp:     string = "Minimum space left for ordinary files. This choice only limits hidden creation; it is not stored in the outer filesystem."
    ui_Desktop:              string = "Desktop"
    ui_AboutThirdParty:      string = "Windows File System Proxy, Copyright (C) Bill Zissimopoulos — github.com/winfsp/winfsp"
    dlg_TitleCreate:         string = "Create a Swag Vault Container"
    dlg_TitleOpen:           string = "Open an Encrypted Container"
    dlg_TitlePassword:       string = "Change the Vault Password"
    dlg_TitleKeyFiles:       string = "Select Key Files"
    dlg_TitleAccessKeyFiles: string = "Choose Key Files"
    dlg_TitleGenerateKey:    string = "Create a Random Key File"
    dlg_TitleChangeKeyFiles: string = "Change the Vault Key Files"
    dlg_TitleResize:         string = "Change Capacity or Camouflage"
    dlg_BtnCreate:           string = "Create"
    dlg_BtnOpen:             string = "Open"
    dlg_BtnAdd:              string = "Add"
    dlg_BtnApply:            string = "Apply"

    // What the line under the title of the list reports, and the boxes a failure opens.
    msg_Ready:                string = "Ready — create a vault or choose one to open."
    msg_OperationStopped:     string = "The operation stopped."
    msg_SystemError:          string = "System error."
    msg_SizeInvalid:          string = "The container size is invalid."
    msg_SizeTooLarge:         string = "The container size is too large."
    msg_SizeMinimum:          string = "The minimum container size is % MiB."
    msg_ChooseCreateFile:     string = "Choose the container file to create."
    msg_FileExists:           string = "This file already exists. Choose a new name to avoid data loss."
    msg_PasswordRequired:     string = "A password is required."
    msg_PasswordMismatch:     string = "The passwords do not match."
    msg_KeyFileCreateFailed:  string = "Could not create the random key file."
    msg_CreateFailed:         string = "Could not create the container."
    msg_Randomizing:          string = "Creating and randomizing the container... %{#0}%%"     // '%{#0}' is the percentage; '%%' is the percent sign itself.
    msg_StopRequested:        string = "Stopping..."
    msg_CreateCanceled:       string = "Container creation canceled. Nothing was left on disk."
    msg_HiddenCreateCanceled: string = "Hidden creation canceled; a previous hidden volume may be damaged."
    msg_ChooseExisting:       string = "Choose an existing container."
    msg_AlreadyMounted:       string = "A drive is already exposing this container."
    msg_UnmountFirst:         string = "This vault is mounted. Unmount it before changing it."
    msg_NoDriveLetter:        string = "No drive letter is available."
    msg_StartingDriver:       string = "Starting the portable filesystem driver..."
    msg_Unmounting:           string = "Synchronizing and unmounting the encrypted drive..."
    msg_CreateStopped:        string = "Container creation stopped."
    msg_Created:              string = "Container created. It is ready to open."
    msg_MountFailed:          string = "Could not mount the virtual disk."
    msg_MountStopped:         string = "Mount stopped."
    msg_Mounted:              string = "Encrypted drive mounted on %."
    msg_MountedReadOnly:      string = "Encrypted drive mounted read only on %."
    msg_MountedProtected:     string = "Drive % is mounted with hidden-volume protection."
    msg_UnmountSyncStopped:   string = "The drive was unmounted, but final synchronization stopped."
    msg_Unmounted:            string = "Drive unmounted safely."
    msg_Resizing:             string = "Resizing the container... %{#0}%%"             // '%{#0}' is the percentage; '%%' is the percent sign itself.
    msg_Camouflaging:         string = "Refreshing physical camouflage... %{#0}%%"     // '%{#0}' is the percentage; '%%' is the percent sign itself.
    msg_ResizeCanceled:       string = "Resizing stopped. The vault kept its previous size."
    msg_ResizeStopped:        string = "Resizing stopped."
    msg_ResizeFailed:         string = "Could not resize the container."
    msg_Resized:              string = "The vault now holds %."
    msg_Camouflaged:          string = "The vault kept its capacity and received a new physical size."
    msg_AutoUnmounted:        string = "Protected drives were unmounted automatically."
    msg_AutoUnmountStopped:   string = "Protected drives were unmounted, but final synchronization stopped."
    msg_ChangingPassword:     string = "Rewriting the key slot..."
    msg_PasswordChanged:      string = "The vault now opens with the new password."
    msg_PasswordRemoved:      string = "The password was removed. Any selected key files are still required."
    msg_PasswordFailed:       string = "Could not change the password."
    msg_PasswordStopped:      string = "The password change stopped."
    msg_KeyFilesChanged:      string = "The vault now opens with the selected key files."
    msg_KeyFilesStopped:      string = "The key-file change stopped."
    msg_KeyFilesFailed:       string = "Could not change the key files."
    msg_HiddenProtected:      string = "Hidden-volume protection prevents this change. Unmount before continuing."

    // What a failure of each [[ErrorKind]] says. The volume layer reports the kind and an
    // English diagnostic for a report; these are the sentences a reader sees instead.
    msg_ErrPasswordOrDamaged: string = "The password or key files are incorrect, or the container is damaged."     // The container did not open, and the format refuses to say which input gave up.
    msg_ErrDamaged:           string = "The container is damaged."                 // An open container no longer reads back what it stored.
    msg_ErrNotFound:          string = "The container could not be found."         // The named container or entry does not exist.
    msg_ErrAlreadyExists:     string = "A file with this name already exists."     // The name is taken.
    msg_ErrAccessDenied:      string = "Access to the container was refused."      // The entry exists and refuses the operation.
    msg_ErrReadOnly:          string = "The vault is mounted read only."           // The container refuses every change.
    msg_ErrSparse:            string = "The container is sparse. Convert it to a fully allocated file before opening it."
    msg_ErrDiskFull:          string = "There is no room left in the container."         // No room is left for blocks, metadata, or key slots.
    msg_ErrIo:                string = "The container could not be read or written."     // The underlying file could not be reached.
    msg_ErrInvalidRequest:    string = "The container cannot answer that request."       // The operation asked for something the container refuses outright.
    msg_ErrElevated:          string = "Swag Vault was started as administrator, so Windows Explorer cannot show its drive. Close it and start it normally."
    msg_ErrDriverUnavailable: string = "The virtual drive could not be started."     // The driver that shows a vault as a drive did not load or start.
    msg_ErrorCode:            string = "Error code: 0x%{X}"     // Under the sentence of a failure, the native code for whoever reports it.
}

private const FrenchStringsName = "lang/fr/vault.tweak"
private const FrenchStrings     = #include("../datas/lang/fr/vault.tweak")

private var g_AppStrings: AppStrings

// Returns the visible strings of Swag Vault in the active language.
func appStrings()->const *AppStrings => &g_AppStrings

// Registers the Swag Vault string table and its embedded translations.
func registerAppStrings(bundle: *Core.Resources.Bundle)
{
    Gui.registerStrings'AppStrings(&g_AppStrings, "vault")
    bundle.addEmbedded(FrenchStringsName, FrenchStrings)
}

// Build-time validation of the embedded translations: a mistyped key in a language
// file is a compile error with its line number, not a runtime fallback.
#run
{
    expect Gui.validateStrings'AppStrings(cast(string, FrenchStrings))
}
