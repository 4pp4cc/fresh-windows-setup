# Debloat profiles and complete option audit

Reviewed 16 October 2026. These are **4pp4cc's curated profiles**, not upstream profiles named Normal/High/Radical. Raphire and Chris Titus Tech receive credit for their work. No performance guarantee.

## Workflow and preserved requirements

Restore point first. The first debloat question selects **1 Normal / 2 High / 3 Radical**. Apps (including verified Chrome), Office, manufacturer catalogs and hardware-ID/SDI work use separate windows. Automatic removals and startup cleanup finish before final power/right-click choices. Radical service restrictions wait until installation/retry work finishes. The IRM window keeps its Ko-fi banner and offers 0 Exit, 1 All, 2 Debloat, 3 Software, 4 Office, 5 Drivers, 6 AMD/NVIDIA, 7 Failed/missing.

All levels preserve Edge/Chrome/Brave, the requested desktop software and Office 2024, Defender's Windows components, App Installer/WinGet, Terminal, Store's platform package, driver frameworks and selected OEM power-management tools. Right-click style is a separate final choice. Apps removed include their app data. User OneDrive folders are kept. Logs and run history are retained. Normal/High do not automatically undo previous Radical changes.

| Level | Intended use | Behavior |
|---|---|---|
| 1 Normal | Recommended | Default Raphire app selection, privacy/AI/advertising cleanup, selected Titus essentials; security/update/store services retained. |
| 2 High | Lower resource use | Normal plus optional app removal, background-app restrictions, reduced effects, Edge/Brave decluttering. Everyday Calculator/Notepad/Paint/Photos/Camera/Snipping Tool/Get Help retained. |
| 3 Radical | Very slow computers; deliberate tradeoff | Nearly all catalogued removable optional apps, reduced location/notifications/companion downloads, Titus service/storage adjustments, then existing requested Defender realtime/Update/indexing restrictions and Store access policy. Windows may refuse/reverse protected changes. Store policy depends on edition. Mobile hotspot/offline files may stop because the Titus service preset changes SharedAccess/CscService. |

## Source versions and coverage

- Raphire feature/app/default catalogs: reviewed current upstream (104 feature entries, 139 app entries). Runtime executes the latest stable release and intersects supported feature IDs. The reviewed stable release 2026.08.24 has 103 feature entries; unreleased Chrome-AI policy is deliberately omitted.
- Chris Titus Tech WinUtil: reviewed **26.10.07**, release SHA256 `eeae69922fbe6354ea4e2a37f705eaa17bdaf45cc7889618a313178a513b13ee`. Reviewed all 67 tweak entries, 33 feature/fix actions, 34 AppX choices, and Minimal/Standard/Advanced/AppxDefault presets. Runtime uses an explicit flat config, not the whole preset and not every mutually exclusive option.
- [Raphire features](https://github.com/Raphire/Win11Debloat/blob/master/Config/Features.json), [Raphire apps](https://github.com/Raphire/Win11Debloat/blob/master/Config/Apps.json), [Titus tweaks](https://github.com/ChrisTitusTech/winutil/blob/26.10.07/config/tweaks.json), [Titus presets](https://github.com/ChrisTitusTech/winutil/blob/26.10.07/config/preset.json), [Titus feature/fix actions](https://github.com/ChrisTitusTech/winutil/blob/26.10.07/config/feature.json).

## Every Raphire feature

A dash means intentionally not selected; opposite Explorer/taskbar/Start/view/snap preferences are not all applied together. Windows build/edition checks still apply.

| ID | Upstream option | Levels / disposition |
|---|---|---|
| RemoveApps | Remove the apps specified with the 'Apps' parameter | Selected app policy below; all levels |
| Apps | The selection of apps to remove, specified as a comma separated list. Use 'Default' (or omit) to use the default apps list | Selected app policy below; all levels |
| RemoveGamingApps | Remove the Xbox App and Xbox Gamebar | Xbox removal runs in every debloat level |
| RemoveHPApps | Remove HP OEM applications | Not selected: optional preference, redundant action or incompatible alternative. |
| CreateRestorePoint | Create a system restore point | Setup verifies a restore point first |
| DisableTelemetry | Disable telemetry, tracking & targeted ads | 1, 2, 3 |
| DisableSuggestions | Disable tips, tricks & suggested content throughout Windows | 1, 2, 3 |
| DisableNotifications | Disable Windows Notifications (From apps and other senders) | 3 |
| DisableLocationServices | Disable Windows location services & app location access | 3 |
| DisableFindMyDevice | Disable Find My Device location tracking | 3 |
| DisableLockscreenTips | Disable tips & tricks on the lock screen | 1, 2, 3 |
| EnableDesktopSpotlight | Enable Windows spotlight desktop background and shortcut | Not selected: optional preference, redundant action or incompatible alternative. |
| DisableDesktopSpotlight | Disable Windows spotlight desktop background | 2, 3 |
| HideDesktopSpotlightIcon | Hide the 'Learn about this picture' desktop shortcut | 2, 3 |
| DisableEdgeAds | Disable ads, suggestions and newsfeed in Edge | 1, 2, 3 |
| DisableCopilot | Disable Microsoft Copilot | 1, 2, 3 |
| DisableRecall | Disable Windows Recall | 1, 2, 3 |
| DisableClickToDo | Disable Click To Do, AI text & image analysis | 1, 2, 3 |
| DisableAISvcAutoStart | Prevent AI service from starting automatically | 1, 2, 3 |
| DisableDVR | Disable Xbox game/screen recording | 1, 2, 3 |
| DisableGameBarIntegration | Disable Game Bar integration | 1, 2, 3 |
| ClearStart | Remove all pinned apps from the start menu for this user only | 3 |
| ClearStartAllUsers | Remove all pinned apps from the start menu for all existing and new users | Not selected: optional preference, redundant action or incompatible alternative. |
| ReplaceStart | Replace the start menu layout for this user only with the provided template file | Not selected: optional preference, redundant action or incompatible alternative. |
| ReplaceStartAllUsers | Replace the start menu layout for all existing and new users with the provided template file | Not selected: optional preference, redundant action or incompatible alternative. |
| DisableStartRecommended | Hide recommended section in the start menu | 1, 2, 3 |
| DisableStartAllApps | Hide 'All Apps' section in the start menu | Excluded: keep access to installed apps |
| DisableStartPhoneLink | Disable Phone Link integration in the start menu | 1, 2, 3 |
| DisableBing | Disable Bing web search & Copilot integration in search | 1, 2, 3 |
| DisableStoreSearchSuggestions | Disable Microsoft Store app suggestions in search | 1, 2, 3 |
| DisableSettings365Ads | Hide Microsoft 365 Copilot ads in Settings Home | 2, 3 |
| DisableSettingsHome | Hide Settings 'Home' page | 2, 3 |
| DisableEdgeAI | Disable AI features in Microsoft Edge | 2, 3 |
| DisableChromeAI | Disable AI features in Google Chrome | Not available in reviewed stable Raphire release; not executed |
| DisablePaintAI | Disable AI features in Paint | 2, 3 |
| DisableNotepadAI | Disable AI features in Notepad | 2, 3 |
| EnableDarkMode | Enable dark theme for system and apps | 1, 2, 3 |
| DisableDragTray | Disable 'Drag Tray' for sharing & moving files | 1, 2, 3 |
| RevertContextMenu | Use classic Windows 10 context menu style | Final user choice: new or classic menu |
| DisableMouseAcceleration | Disable Enhance Pointer Precision (mouse acceleration) | Not selected: optional preference, redundant action or incompatible alternative. |
| DisableStickyKeys | Disable Sticky Keys keyboard shortcut (5x shift) | Not selected: optional preference, redundant action or incompatible alternative. |
| DisableWindowSnapping | Disable window snapping | Not selected: optional preference, redundant action or incompatible alternative. |
| DisableSnapAssist | Disable showing app suggestions when snapping windows | Not selected: optional preference, redundant action or incompatible alternative. |
| DisableSnapLayouts | Hide snap layout flyout at top of screen and on maximize button | Not selected: optional preference, redundant action or incompatible alternative. |
| HideTabsInAltTab | Hide tabs from apps when snapping or pressing Alt+Tab | 2, 3 |
| Show3TabsInAltTab | Show 3 tabs from apps when snapping or pressing Alt+Tab | Not selected: optional preference, redundant action or incompatible alternative. |
| Show5TabsInAltTab | Show 5 tabs from apps when snapping or pressing Alt+Tab | Not selected: optional preference, redundant action or incompatible alternative. |
| Show20TabsInAltTab | Show 20 tabs from apps when snapping or pressing Alt+Tab | Not selected: optional preference, redundant action or incompatible alternative. |
| TaskbarAlignLeft | Align taskbar to the left | Not selected: optional preference, redundant action or incompatible alternative. |
| HideSearchTb | Hide search icon from the taskbar | 1, 2, 3 |
| ShowSearchIconTb | Show search icon on the taskbar | Not selected: optional preference, redundant action or incompatible alternative. |
| ShowSearchLabelTb | Show search icon with label on the taskbar | Not selected: optional preference, redundant action or incompatible alternative. |
| ShowSearchBoxTb | Show search box on the taskbar | Not selected: optional preference, redundant action or incompatible alternative. |
| HideTaskview | Hide 'Task view' button on the taskbar | 1, 2, 3 |
| DisableWidgets | Disable widgets on the taskbar & lock screen | 1, 2, 3 |
| HideChat | Hide Chat (meet now) icon on the taskbar | 1, 2, 3 |
| DisableStorageSense | Disable Storage Sense automatic disk cleanup | Not selected: optional preference, redundant action or incompatible alternative. |
| DisableFastStartup | Disable fast start-up | Excluded: preserve machine defaults |
| DisableBitlockerAutoEncryption | Disable BitLocker automatic device encryption | Excluded: preserve encryption |
| DisableModernStandbyNetworking | Disable Modern Standby network connectivity | Excluded: preserve hardware sleep compatibility |
| EnableEndTask | Show 'End Task' option in taskbar context menu | 1, 2, 3 |
| EnableLastActiveClick | Enable 'Last Active Click' behavior for taskbar apps | Not selected: optional preference, redundant action or incompatible alternative. |
| CombineTaskbarAlways | Always combine taskbar buttons and hide labels for the main display | Not selected: optional preference, redundant action or incompatible alternative. |
| CombineMMTaskbarAlways | Always combine taskbar buttons and hide labels for secondary displays | Not selected: optional preference, redundant action or incompatible alternative. |
| CombineTaskbarWhenFull | Combine taskbar buttons and hide labels when taskbar is full for the main display | Not selected: optional preference, redundant action or incompatible alternative. |
| CombineMMTaskbarWhenFull | Combine taskbar buttons and hide labels when taskbar is full for secondary displays | Not selected: optional preference, redundant action or incompatible alternative. |
| CombineTaskbarNever | Never combine taskbar buttons and show labels for the main display | Not selected: optional preference, redundant action or incompatible alternative. |
| CombineMMTaskbarNever | Never combine taskbar buttons and show labels for secondary displays | Not selected: optional preference, redundant action or incompatible alternative. |
| MMTaskbarModeAll | Show app icons on all taskbars | Not selected: optional preference, redundant action or incompatible alternative. |
| MMTaskbarModeMainActive | Show app icons on main taskbar and on taskbar where the window is open | Not selected: optional preference, redundant action or incompatible alternative. |
| MMTaskbarModeActive | Show app icons only on taskbar where the window is open | Not selected: optional preference, redundant action or incompatible alternative. |
| ExplorerToHome | Change the default location that File Explorer opens to 'Home' | Not selected: optional preference, redundant action or incompatible alternative. |
| ExplorerToThisPC | Change the default location that File Explorer opens to 'This PC' | 1, 2, 3 |
| ExplorerToDownloads | Change the default location that File Explorer opens to 'Downloads' | Not selected: optional preference, redundant action or incompatible alternative. |
| ExplorerToOneDrive | Change the default location that File Explorer opens to 'OneDrive' | Not selected: optional preference, redundant action or incompatible alternative. |
| ShowKnownFileExt | Show file extensions for known file types | 1, 2, 3 |
| ShowHiddenFolders | Show hidden files, folders and drives | Not selected: optional preference, redundant action or incompatible alternative. |
| HideDupliDrive | Hide duplicate removable drive entries | Not selected: optional preference, redundant action or incompatible alternative. |
| HideHome | Hide 'Home' from navigation pane | 2, 3 |
| HideGallery | Hide 'Gallery' from navigation pane | 2, 3 |
| DisableTransparency | Disable transparency effects | 2, 3 |
| DisableAnimations | Disable animations and visual effects | 2, 3 |
| DisableUpdateASAP | Prevent getting updates as soon as they're available | 1, 2, 3 |
| PreventUpdateAutoReboot | Prevent automatic restarts after updates while signed in | 1, 2, 3 |
| DisableDeliveryOptimization | Disable sharing downloaded updates with other PCs | 1, 2, 3 |
| DisableDeviceAutoAppDownload | Prevent Windows from auto-installing device companion apps | 3 |
| ForceRemoveEdge | Forcefully uninstall Microsoft Edge. NOT RECOMMENDED! | Excluded: Edge is required and remains the default |
| HideOnedrive | Hide 'OneDrive' from navigation pane | Not selected: optional preference, redundant action or incompatible alternative. |
| Hide3dObjects | Hide '3D objects' folder under 'This PC' | 1, 2, 3 |
| HideMusic | Hide 'Music' folder under 'This PC' | Not selected: optional preference, redundant action or incompatible alternative. |
| AddFoldersToThisPC | Add common folders back to 'This PC' page | Not selected: optional preference, redundant action or incompatible alternative. |
| HideIncludeInLibrary | Hide 'Include in library' option in the context menu | Not selected: optional preference, redundant action or incompatible alternative. |
| HideGiveAccessTo | Hide 'Give access to' option in the context menu | Not selected: optional preference, redundant action or incompatible alternative. |
| HideShare | Hide 'Share' option in the context menu | Not selected: optional preference, redundant action or incompatible alternative. |
| DisableBraveBloat | Disable bloat in Brave browser (AI, Crypto, etc.) | 2, 3 |
| EnableWindowsSandbox | Enable Windows Sandbox | Excluded: not debloat; changes virtualization |
| EnableWindowsSubsystemForLinux | Enable Windows Subsystem for Linux | Excluded: not debloat; changes virtualization |
| ShowDriveLettersFirst | Show drive letters before drive label | Not selected: optional preference, redundant action or incompatible alternative. |
| ShowDriveLettersLast | Show drive letters after drive label | Not selected: optional preference, redundant action or incompatible alternative. |
| ShowNetworkDriveLettersFirst | Show network drive letters before drive label | Not selected: optional preference, redundant action or incompatible alternative. |
| HideDriveLetters | Hide all drive letters | Not selected: optional preference, redundant action or incompatible alternative. |
| StartAllAppsCategory | Show All Apps in Category view (Default) | Not selected: optional preference, redundant action or incompatible alternative. |
| StartAllAppsGrid | Show All Apps in Grid view | Not selected: optional preference, redundant action or incompatible alternative. |
| StartAllAppsList | Show All Apps in List view | Not selected: optional preference, redundant action or incompatible alternative. |

## Every Titus tweak/toggle/action

| ID | Upstream option | Levels | Disposition |
|---|---|---|---|
| WPFTweaksActivity | Activity History - Disable | 1, 2, 3 | Explicit WinUtil config selection; reviewed definitions, no blanket preset. |
| WPFTweaksHiber | Hibernation - Disable | — | Excluded: preserve hibernation availability and laptop recovery. |
| WPFTweaksWidget | Widgets - Remove | — | Covered by Raphire. |
| WPFTweaksRevertStartMenu | Start Menu Previous Layout - Enable | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFTweaksDisableStoreSearch | Microsoft Store Recommended Search Results - Disable | — | Covered by Raphire. |
| WPFTweaksLocation | Location Tracking - Disable | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFTweaksServices | Services - Set to Manual | 3 | Explicit WinUtil config selection; reviewed definitions, no blanket preset. |
| WPFTweaksBraveDebloat | Brave Browser - Debloat | 2, 3 | Explicit WinUtil config selection; reviewed definitions, no blanket preset. |
| WPFTweaksDisableWarningForUnsignedRdp | RDP Unsigned File Warnings - Disable | — | Excluded: preserve security warnings. |
| WPFTweaksEdgeDebloat | Microsoft Edge - Debloat | 2, 3 | Explicit WinUtil config selection; reviewed definitions, no blanket preset. |
| WPFTweaksConsumerFeatures | ConsumerFeatures - Disable | 1, 2, 3 | Explicit WinUtil config selection; reviewed definitions, no blanket preset. |
| WPFTweaksTelemetry | Telemetry - Disable | — | Raphire handles privacy. Excludes this duplicate script's Defender sample-submission change. |
| WPFTweaksDeliveryOptimization | Delivery Optimization - Disable | 1, 2, 3 | Explicit WinUtil config selection; reviewed definitions, no blanket preset. |
| WPFTweaksRemoveEdge | Microsoft Edge - Remove | — | Excluded: required browser. |
| WPFTweaksDisableBitLocker | BitLocker - Disable | — | Excluded: preserve encryption. |
| WPFTweaksUTC | Date & Time - Set Time to UTC | — | Excluded: dual-boot-specific. |
| WPFTweaksRemoveOneDrive | Microsoft OneDrive - Remove | — | Covered by the dedicated OneDrive uninstaller. |
| WPFTweaksRemoveHomeAndGallery | File Explorer Home and Gallery - Disable | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFTweaksDisplay | Visual Effects - Set to Best Performance | 2, 3 | Explicit WinUtil config selection; reviewed definitions, no blanket preset. |
| WPFTweaksReservedStorage | Disable Reserved Storage | 3 | Explicit WinUtil config selection; reviewed definitions, no blanket preset. |
| WPFTweaksRestorePoint | Restore Point - Create | — | Setup creates/verifies the restore point before parallel work. |
| WPFTweaksEndTaskOnTaskbar | End Task With Right Click - Enable | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFTweaksStorage | Storage Sense - Disable | 3 | Explicit WinUtil config selection; reviewed definitions, no blanket preset. |
| WPFTweaksWindowsAI | Windows AI - Disable And Remove | — | Raphire handles AI; excludes extra protected-package EndOfLife manipulation. |
| WPFTweaksWPBT | Windows Platform Binary Table (WPBT) - Disable | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFTweaksPreventDeviceMetadataFromNetwork | Prevent Device Companion Apps | — | Radical uses Raphire's equivalent; leave other levels' driver provisioning intact. |
| WPFTweaksRazerBlock | Razer Software Auto-Install - Disable | — | Excluded: blocks user-requested vendor software. |
| WPFTweaksLogiBlock | Logitech Download Assistant Auto-Install - Disable | — | Excluded: preserve hardware/software setup choices. |
| WPFTweaksDisableNotifications | System Tray Notifications & Calendar - Disable | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFTweaksBlockAdobeNet | Adobe URL Block List - Enable | — | Excluded: activation/telemetry host blocklist unrelated to requested debloat. |
| WPFTweaksRightClickMenu | Right-Click Menu Previous Layout - Enable | — | Final menu choice, independent of preset. |
| WPFTweaksDiskCleanup | Disk Cleanup - Run | — | Excluded: update cleanup conflicts with parallel installation and restore/recovery. |
| WPFTweaksDeleteTempFiles | Temporary Files - Remove | — | Excluded: blanket TEMP deletion conflicts with parallel installers and retained logs. |
| WPFTweaksIPv46 | IPv6 - Set IPv4 as Preferred | — | Excluded: preserve networking. |
| WPFTweaksTeredo | Teredo - Disable | — | Excluded: preserve networking. |
| WPFTweaksDisableIPv6 | IPv6 - Disable | — | Excluded: preserve networking. |
| WPFTweaksDisableBGapps | Background Apps - Disable | 2, 3 | Explicit WinUtil config selection; reviewed definitions, no blanket preset. |
| WPFTweaksDisableExplorerAutoDiscovery | File Explorer Automatic Folder Discovery - Disable | 1, 2, 3 | Explicit WinUtil config selection; reviewed definitions, no blanket preset. |
| WPFToggleDetailedBSoD | BSoD Verbose Mode | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleBatteryPercentage | System Tray Battery Percentage | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleDarkMode | Dark Theme for Windows | — | Covered by verified common dark theme. |
| WPFToggleShowExt | File Explorer File Extensions | — | Covered by Raphire/common Explorer settings. |
| WPFToggleHiddenFiles | File Explorer Hidden Files | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleVerboseLogon | Logon Verbose Mode | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleNewOutlook | Microsoft Outlook New Version | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleScrollbars | Scrollbars Always Visible | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFMultiplaneOverlay | Multiplane Overlay | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleMouseAcceleration | Mouse Acceleration | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleNumLock | Num Lock on Startup | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleWindowSnapping | Window Snapping | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleStandbyFix | S0 Sleep Network Connectivity | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleS3Sleep | S3 Sleep | — | Excluded: firmware-dependent; preserve supported sleep states. |
| WPFToggleHideSettingsHome | Settings Home Page | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleBingSearch | Start Menu Bing Search | — | Covered by Raphire. |
| WPFToggleLoginBlur | Logon Screen Acrylic Blur | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleDisableLockscreen | Lock Screen - Disable | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleStartMenuRecommendations | Start Menu Recommendations | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleStickyKeys | Sticky Keys | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleTaskbarAlignment | Taskbar Centered Icons | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleTaskbarSearch | Taskbar Search Icon | — | Covered by common taskbar settings. |
| WPFToggleTaskView | Taskbar Task View Icon | — | Covered by common taskbar settings. |
| WPFToggleGameMode | Game Mode | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFToggleLongPaths | Enable Long Paths | — | Not selected: optional preference or redundant action; preserve default behavior. |
| WPFOOSUbutton | O&O ShutUp10++ - Run | — | Excluded: separate third-party utility with additional settings not blindly applied. |
| WPFchangedns | DNS - Set to: | — | Excluded: preserve networking/DNS. |
| WPFAddUltPerf | Ultimate Performance Profile - Enable | — | Final power-profile choice; high performance in both choices. |
| WPFRemoveUltPerf | Ultimate Performance Profile - Disable | — | Excluded: conflicts with requested high-performance profiles. |

## Every Titus feature/fix action

Feature installation and troubleshooting tools are not debloat levels. They are excluded unless called separately by setup for their specific purpose. No Hyper-V/WSL/Sandbox/SSH server, autologon, networking reset or PowerShell profile is silently enabled.

| ID | Upstream option | Disposition |
|---|---|---|
| WPFFeaturesdotnet | .NET Framework (Versions 2, 3, 4) - Enable | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFFixesNTPPool | NTP Server - Enable | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFFeatureshyperv | Hyper-V - Enable | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFFeatureslegacymedia | Legacy Media Components (WMP, DirectPlay) - Enable | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFFeaturewsl | Windows Subsystem for Linux (WSL) - Enable | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFFeaturenfs | Network File System (NFS) - Enable | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFFeatureRegBackup | Registry Backup (Daily Task 12:30am) - Enable | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFFeatureEnableLegacyRecovery | Legacy F8 Boot Recovery - Enable | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFFeatureDisableLegacyRecovery | Legacy F8 Boot Recovery - Disable | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFFeaturesSandbox | Windows Sandbox - Enable | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFFeatureInstall | Install Features | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelAutologin | AutoLogon - Run | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFFixesUpdate | Windows Update - Reset | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFFixesNetwork | Network - Reset | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelDISM | System Corruption Scan - Run | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFFixesWinget | WinGet - Reinstall | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelComputer | Computer Management | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelControl | Control Panel | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelMouse | Mouse Properties | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelNetwork | Network Connections | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelPower | Power Panel | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelPrinter | Printer Panel | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelPrograms | Programs and Features | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelRegion | Region | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelSecurity | Security and Maintenance | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelSound | Sound Settings | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelSystem | System Properties | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelTimedate | Time and Date | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelFirewall | Windows Defender Firewall | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFPanelRestore | Windows Restore | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFWinUtilInstallPSProfile | CTT PowerShell Profile - Install | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFWinUtilUninstallPSProfile | CTT PowerShell Profile - Remove | Excluded from debloat presets; separate feature/fix/control panel. |
| WPFWinUtilSSHServer | OpenSSH Server - Enable | Excluded from debloat presets; separate feature/fix/control panel. |

## Every Raphire app entry

The table is the policy review, not a promise that an app is installed or removable on every Windows build. Additional Titus AppX choices are merged as optional entries; duplicates are removed. Runtime counts can change with the selected stable Raphire catalog.

| App ID(s) | App | Levels selecting removal |
|---|---|---|
| Clipchamp.Clipchamp | Clipchamp | 1, 2, 3 |
| Microsoft.3DBuilder | 3D Builder | 1, 2, 3 |
| Microsoft.549981C3F5F10 | Cortana | 1, 2, 3 |
| Microsoft.BingFinance | Bing Finance | 1, 2, 3 |
| Microsoft.BingFoodAndDrink | Bing Food And Drink | 1, 2, 3 |
| Microsoft.BingHealthAndFitness | Bing Health And Fitness | 1, 2, 3 |
| Microsoft.BingNews | Microsoft News | 1, 2, 3 |
| Microsoft.BingSports | Bing Sports | 1, 2, 3 |
| Microsoft.BingTranslator | Bing Translator | 1, 2, 3 |
| Microsoft.BingTravel | Bing Travel | 1, 2, 3 |
| Microsoft.BingWeather | Bing Weather | 1, 2, 3 |
| XP9CXNGPPJ97XX | Microsoft Copilot | 1, 2, 3 |
| Microsoft.Windows.AIHub | Copilot+ AI Hub | 1, 2, 3 |
| Microsoft.PCManager | Microsoft PC Manager | 1, 2, 3 |
| Microsoft.Getstarted | Get Started | 1, 2, 3 |
| Microsoft.Messaging | Messaging | 1, 2, 3 |
| Microsoft.Microsoft3DViewer | 3D Viewer | 1, 2, 3 |
| Microsoft.MicrosoftJournal | Microsoft Journal | 1, 2, 3 |
| Microsoft.MicrosoftOfficeHub | Office Hub | 1, 2, 3 |
| Microsoft.MicrosoftPowerBIForWindows | Power BI | 1, 2, 3 |
| Microsoft.MicrosoftSolitaireCollection | Solitaire Collection | 1, 2, 3 |
| Microsoft.MicrosoftStickyNotes | Sticky Notes | 1, 2, 3 |
| Microsoft.MixedReality.Portal | Mixed Reality Portal | 1, 2, 3 |
| Microsoft.NetworkSpeedTest | Network Speed Test | 1, 2, 3 |
| Microsoft.Office.OneNote | OneNote | 1, 2, 3 |
| Microsoft.Office.Sway | Sway | 1, 2, 3 |
| Microsoft.OneConnect | One Connect | 1, 2, 3 |
| Microsoft.Print3D | Print 3D | 1, 2, 3 |
| Microsoft.PowerAutomateDesktop | Power Automate | 1, 2, 3 |
| Microsoft.SkypeApp | Skype (UWP) | 1, 2, 3 |
| Microsoft.Todos | Microsoft To Do | 1, 2, 3 |
| Microsoft.Windows.DevHome | Dev Home | 1, 2, 3 |
| Microsoft.WindowsAlarms | Alarms & Clock | 1, 2, 3 |
| Microsoft.WindowsFeedbackHub | Feedback Hub | 1, 2, 3 |
| Microsoft.WindowsMaps | Windows Maps | 1, 2, 3 |
| Microsoft.WindowsSoundRecorder | Sound Recorder | 1, 2, 3 |
| Microsoft.XboxApp | Xbox Console Companion | 1, 2, 3 |
| Microsoft.ZuneVideo | Movies & TV | 1, 2, 3 |
| MicrosoftCorporationII.MicrosoftFamily | Family Safety | 1, 2, 3 |
| MicrosoftCorporationII.QuickAssist | Quick Assist | 1, 2, 3 |
| MicrosoftTeams | Microsoft Teams (Old) | 1, 2, 3 |
| MSTeams | Microsoft Teams (New) | 1, 2, 3 |
| ACGMediaPlayer | ACG Media Player | 1, 2, 3 |
| ActiproSoftwareLLC | Actipro Software | 1, 2, 3 |
| AdobeSystemsIncorporated.AdobePhotoshopExpress | Adobe Photoshop Express | 1, 2, 3 |
| Amazon.com.Amazon | Amazon | 1, 2, 3 |
| AmazonVideo.PrimeVideo | Prime Video | 1, 2, 3 |
| Asphalt8Airborne | Asphalt 8 | 1, 2, 3 |
| AutodeskSketchBook | Autodesk SketchBook | 1, 2, 3 |
| CaesarsSlotsFreeCasino | Caesars Slots | 1, 2, 3 |
| COOKINGFEVER | Cooking Fever | 1, 2, 3 |
| CyberLinkMediaSuiteEssentials | CyberLink Media Suite | 1, 2, 3 |
| DisneyMagicKingdoms | Disney Magic Kingdoms | 1, 2, 3 |
| Disney.37853FC22B2CE | Disney+ | 1, 2, 3 |
| DrawboardPDF | Drawboard PDF | 1, 2, 3 |
| Duolingo-LearnLanguagesforFree | Duolingo | 1, 2, 3 |
| FACEBOOK.FACEBOOK | Facebook | 1, 2, 3 |
| FarmVille2CountryEscape | FarmVille 2 | 1, 2, 3 |
| Flipboard | Flipboard | 1, 2, 3 |
| HiddenCity | Hidden City | 1, 2, 3 |
| HULULLC.HULUPLUS | Hulu | 1, 2, 3 |
| iHeartRadio | iHeartRadio | 1, 2, 3 |
| Facebook.Instagram | Instagram | 1, 2, 3 |
| king.com.BubbleWitch3Saga | Bubble Witch 3 | 1, 2, 3 |
| king.com.CandyCrushSaga | Candy Crush Saga | 1, 2, 3 |
| king.com.CandyCrushSodaSaga | Candy Crush Soda | 1, 2, 3 |
| LinkedInforWindows | LinkedIn | 1, 2, 3 |
| MarchofEmpires | March of Empires | 1, 2, 3 |
| 4DF9E0F8.Netflix | Netflix | 1, 2, 3 |
| NYTCrossword | NYT Crossword | 1, 2, 3 |
| OneCalendar | One Calendar | 1, 2, 3 |
| PandoraMediaInc | Pandora | 1, 2, 3 |
| PhototasticCollage | Phototastic Collage | 1, 2, 3 |
| PicsArt-PhotoStudio | PicsArt | 1, 2, 3 |
| PolarrPhotoEditorAcademicEdition | Polarr Photo Editor | 1, 2, 3 |
| flaregamesGmbH.RoyalRevolt | Royal Revolt | 1, 2, 3 |
| Sidia.LiveWallpaper | Live Wallpaper | 1, 2, 3 |
| SlingTV | Sling TV | 1, 2, 3 |
| SpotifyAB.SpotifyMusic | Spotify | 1, 2, 3 |
| BytedancePte.Ltd.TikTok | TikTok | 1, 2, 3 |
| TuneInRadio | TuneIn Radio | 1, 2, 3 |
| WinZipUniversal | WinZip | 1, 2, 3 |
| Microsoft.BingSearch | Bing Search | 2, 3 |
| Microsoft.Edge, XPFFTQ037JWMHS | Microsoft Edge | Protected / retained |
| Microsoft.GamingApp | Xbox Gaming App | 2, 3 |
| Microsoft.GetHelp | Get Help | 3 |
| Microsoft.M365Companions | Microsoft 365 Companions | 2, 3 |
| Microsoft.MSPaint | Paint 3D | 2, 3 |
| Microsoft.OneDrive | OneDrive | 2, 3 |
| Microsoft.OutlookForWindows | Outlook for Windows | 2, 3 |
| Microsoft.Paint | Paint | 3 |
| Microsoft.People | People | 3 |
| Microsoft.RemoteDesktop | Remote Desktop | 2, 3 |
| Microsoft.ScreenSketch | Snipping Tool | 3 |
| Microsoft.StartExperiencesApp | Widgets Experience | 2, 3 |
| Microsoft.Whiteboard | Whiteboard | 2, 3 |
| Microsoft.Windows.Photos | Photos | 3 |
| Microsoft.WindowsCalculator | Calculator | 3 |
| Microsoft.WindowsCamera | Camera | 3 |
| Microsoft.windowscommunicationsapps | Mail & Calendar | 3 |
| Microsoft.WindowsNotepad | Notepad | 3 |
| Microsoft.WindowsStore | Microsoft Store | Protected / retained |
| Microsoft.WindowsTerminal | Windows Terminal | Protected / retained |
| Microsoft.Xbox.TCUI | Xbox TCUI Framework | 2, 3 |
| Microsoft.XboxGameOverlay | Xbox Game Overlay | 2, 3 |
| Microsoft.XboxGamingOverlay | Xbox Gaming Overlay | 2, 3 |
| Microsoft.XboxIdentityProvider | Xbox Identity Provider | 2, 3 |
| Microsoft.XboxSpeechToTextOverlay | Xbox Speech To Text | 2, 3 |
| Microsoft.YourPhone | Phone Link | 2, 3 |
| Microsoft.ZuneMusic | Media Player | 2, 3 |
| MicrosoftWindows.CrossDevice | Cross Device Experience | 2, 3 |
| MicrosoftWindows.Client.WebExperience | Windows Web Experience Pack | 2, 3 |
| Microsoft.WidgetsPlatformRuntime | Widgets Platform Runtime | 2, 3 |
| LGElectronics.LGMonitorApp | LG Monitor App | 2, 3 |
| AD2F1837.HPAIExperienceCenter | HP AI Experience Center | 2, 3 |
| AD2F1837.HPConnectedMusic | HP Connected Music | 2, 3 |
| AD2F1837.HPConnectedPhotopoweredbySnapfish | HP Connected Photo | 2, 3 |
| AD2F1837.HPDesktopSupportUtilities | HP Desktop Support Utilities | 2, 3 |
| AD2F1837.HPEasyClean | HP Easy Clean | 2, 3 |
| AD2F1837.HPFileViewer | HP File Viewer | 2, 3 |
| AD2F1837.HPJumpStarts | HP JumpStarts | 2, 3 |
| AD2F1837.HPPCHardwareDiagnosticsWindows | HP PC Hardware Diagnostics | 2, 3 |
| AD2F1837.HPPowerManager | HP Power Manager | Protected / retained |
| AD2F1837.HPPrinterControl | HP Printer Control | 2, 3 |
| AD2F1837.HPPrivacySettings | HP Privacy Settings | 2, 3 |
| AD2F1837.HPQuickDrop | HP QuickDrop | 2, 3 |
| AD2F1837.HPQuickTouch | HP QuickTouch | 2, 3 |
| AD2F1837.HPRegistration | HP Registration | 2, 3 |
| AD2F1837.HPSupportAssistant | HP Support Assistant | 2, 3 |
| AD2F1837.HPSureShieldAI | HP Sure Shield AI | 2, 3 |
| AD2F1837.HPSystemInformation | HP System Information | 2, 3 |
| AD2F1837.HPWelcome | HP Welcome | 2, 3 |
| AD2F1837.HPWorkWell | HP WorkWell | 2, 3 |
| AD2F1837.myHP | myHP | 2, 3 |
| E046963F.LenovoCompanion | Lenovo Vantage | Protected / retained |
| LenovoCompanyLimited.LenovoVantageService | Lenovo Vantage Service | Protected / retained |
| DellInc.DellSupportAssistforPCs | Dell SupportAssist | 2, 3 |
| DellInc.DellDigitalDelivery | Dell Digital Delivery Services | 2, 3 |
| DellInc.DellMobileConnect | Dell Mobile Connect | 2, 3 |

## Every Titus AppX choice

| Selection ID | Package ID | App | Levels selecting removal |
|---|---|---|---|
| WPFAppxMicrosoft_WindowsFeedbackHub | Microsoft.WindowsFeedbackHub | Feedback Hub | 1, 2, 3 |
| WPFAppxMicrosoft_GetHelp | Microsoft.GetHelp | Get Help | 3 |
| WPFAppxMicrosoft_OutlookForWindows | Microsoft.OutlookForWindows | Outlook for Windows | 2, 3 |
| WPFAppxMSTeams | MSTeams | Microsoft Teams | 1, 2, 3 |
| WPFAppxClipchamp_Clipchamp | Clipchamp.Clipchamp | Clipchamp | 1, 2, 3 |
| WPFAppxMicrosoft_MicrosoftOfficeHub | Microsoft.MicrosoftOfficeHub | Microsoft 365 | 1, 2, 3 |
| WPFAppxMicrosoft_ZuneMusic | Microsoft.ZuneMusic | Media Player | 2, 3 |
| WPFAppxMicrosoft_BingSearch | Microsoft.BingSearch | Bing Search | 2, 3 |
| WPFAppxMicrosoftCorporationII_QuickAssist | MicrosoftCorporationII.QuickAssist | Quick Assist | 1, 2, 3 |
| WPFAppxMicrosoft_WindowsDevHome | Microsoft.Windows.DevHome | Dev Home | 1, 2, 3 |
| WPFAppxMicrosoft_WindowsCrossDevice | MicrosoftWindows.CrossDevice | Mobile Devices | 2, 3 |
| WPFAppxMicrosoft_Todos | Microsoft.Todos | To Do | 1, 2, 3 |
| WPFAppxMicrosoft_PowerAutomateDesktop | Microsoft.PowerAutomateDesktop | Power Automate | 1, 2, 3 |
| WPFAppxMicrosoft_YourPhone | Microsoft.YourPhone | Phone Link | 2, 3 |
| WPFAppxMicrosoft_MicrosoftStickyNotes | Microsoft.MicrosoftStickyNotes | Sticky Notes | 1, 2, 3 |
| WPFAppxMicrosoft_WindowsSoundRecorder | Microsoft.WindowsSoundRecorder | Sound Recorder | 1, 2, 3 |
| WPFAppxMicrosoft_WindowsAlarms | Microsoft.WindowsAlarms | Clock | 1, 2, 3 |
| WPFAppxMicrosoft_Paint | Microsoft.Paint | Paint | 3 |
| WPFAppxMicrosoft_WindowsNotepad | Microsoft.WindowsNotepad | Notepad | 3 |
| WPFAppxMicrosoft_ScreenSketch | Microsoft.ScreenSketch | Snipping Tool | 3 |
| WPFAppxMicrosoft_Copilot | Microsoft.Copilot | Copilot | 2, 3 |
| WPFAppxMicrosoft_WindowsCalculator | Microsoft.WindowsCalculator | Calculator | 3 |
| WPFAppxMicrosoft_WindowsCamera | Microsoft.WindowsCamera | Camera | 3 |
| WPFAppxMicrosoft_WindowsPhotos | Microsoft.Windows.Photos | Photos | 3 |
| WPFAppxMicrosoft_BingNews | Microsoft.BingNews | News | 1, 2, 3 |
| WPFAppxMicrosoft_BingWeather | Microsoft.BingWeather | Weather | 1, 2, 3 |
| WPFAppxMicrosoft_GamingApp | Microsoft.GamingApp | Xbox App | 2, 3 |
| WPFAppxMicrosoft_XboxGamingOverlay | Microsoft.XboxGamingOverlay | Xbox Game Bar | 2, 3 |
| WPFAppxMicrosoft_XboxIdentityProvider | Microsoft.XboxIdentityProvider | Xbox Identity Provider | 2, 3 |
| WPFAppxMicrosoft_XboxSpeechToTextOverlay | Microsoft.XboxSpeechToTextOverlay | Xbox Speech To Text Overlay | 2, 3 |
| WPFAppxMicrosoft_Xbox_TCUI | Microsoft.Xbox.TCUI | Xbox TCUI | 2, 3 |
| WPFAppxMicrosoft_StartExperiencesApp | Microsoft.StartExperiencesApp | Start Experiences App | 2, 3 |
| WPFAppxMicrosoft_MicrosoftSolitaireCollection | Microsoft.MicrosoftSolitaireCollection | Solitaire Collection | 1, 2, 3 |
| WPFAppxMicrosoft_ZuneVideo | Microsoft.ZuneVideo | Movies & TV | 1, 2, 3 |

## Update profiles and radical limits

The reviewed WinUtil update actions are Default, Security and Disable. Normal/High keep Windows Update operational; Radical uses the setup's explicit logged NoAutoUpdate/service restrictions after workers finish. Defender realtime restriction is an existing 4pp4cc option, not a claim that upstream supplies an official preset named Radical. The setup does not remove the Defender executable, disable Tamper Protection or obfuscate activation commands. Protected changes are reported if Windows refuses them.
