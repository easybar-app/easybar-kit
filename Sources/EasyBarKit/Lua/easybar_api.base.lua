-- EasyBar Lua API stub version: __EASYBAR_VERSION__
---@meta

---Logging levels accepted by `easybar.log(...)`.
---@alias EasyBarLevel
---Verbose diagnostic logging intended for deep debugging.
---| '"trace"'
---Useful development-time logging with lower volume than `trace`.
---| '"debug"'
---Normal informational logging.
---| '"info"'
---Warnings about unexpected but recoverable conditions.
---| '"warn"'
---Errors that indicate a widget or runtime problem.
---| '"error"'

---Literal node kinds accepted by `easybar.add(...)`.
---In normal widget code, prefer the `easybar.kind.*` constants over raw strings.
---@alias EasyBarKind
---Basic widget node for most text, icon, and interaction cases.
---| '"item"'
---Horizontal layout container for child nodes.
---| '"row"'
---Vertical layout container for child nodes.
---| '"column"'
---Shared container that lets multiple child nodes look and behave like one widget.
---| '"group"'
---Popup container node used for richer attached surfaces.
---| '"popup"'
---Interactive scalar control that emits slider events.
---| '"slider"'
---Read-only scalar meter for current numeric values.
---| '"progress"'
---Combined progress-style display with slider interaction.
---| '"progress_slider"'
---Compact line-chart style node for a list of samples.
---| '"sparkline"'
---Specialized workspace or space indicator style node.
---| '"spaces"'

---Mouse button names that may appear in event payloads.
---@alias EasyBarMouseButton
---Primary mouse button.
---| '"left"'
---Secondary mouse button.
---| '"right"'
---Middle mouse button.
---| '"middle"'

---Scroll directions that may appear in event payloads.
---@alias EasyBarScrollDirection
---Upward scrolling.
---| '"up"'
---Downward scrolling.
---| '"down"'
---Leftward scrolling.
---| '"left"'
---Rightward scrolling.
---| '"right"'

---Root-level bar positions used by top-level nodes.
---@alias EasyBarRootPosition
---Left bar region.
---| '"left"'
---Center bar region.
---| '"center"'
---Right bar region.
---| '"right"'

---Placement string for a node.
---At the root level this is usually `left`, `center`, or `right`; popup children use `popup.<parent-id>`.
---@alias EasyBarPosition string

---Font override fields used by label and icon content.
---@class (exact) EasyBarFontProps
---@field size? number Font size in points.

---Detailed label configuration used when a plain label value is not enough.
---@class (exact) EasyBarLabelProps
---@field string? string Label text.
---@field color? string Hex color override for the label.
---@field font? EasyBarFontProps Label font overrides.

---Detailed icon configuration used when a plain icon value is not enough.
---@class (exact) EasyBarIconProps
---@field string? string Icon glyph text.
---@field color? string Hex color override for the icon.
---@field font? EasyBarFontProps Icon font overrides.
---@field image? EasyBarImage Structured image source to render instead of icon text.
---@field offset_x? number Horizontal visual icon offset in points without changing layout spacing.
---@field offset_y? number Vertical visual icon offset in points without changing layout spacing.

---Image configuration for nodes that render an image instead of text.
---@class (exact) EasyBarImage
---@field path? string Filesystem path of an image. Mutually exclusive with `svg`.
---@field svg? string Inline SVG source. Mutually exclusive with `path`.
---@field size? number Image size in points.
---@field corner_radius? number Image corner radius in points.

---Shared surface styling fields used by nodes and popups.
---@class (exact) EasyBarBackgroundProps
---@field color? string Background fill color.
---@field border_color? string Border stroke color.
---@field border_width? number Border width in points.
---@field corner_radius? number Corner radius in points.
---@field padding_left? number Left padding in points.
---@field padding_right? number Right padding in points.
---@field padding_top? number Top padding in points.
---@field padding_bottom? number Bottom padding in points.

---Outer spacing fields that push a node away from surrounding content.
---@class (exact) EasyBarMarginProps
---@field margin_left? number Left margin in points.
---@field margin_right? number Right margin in points.
---@field margin_top? number Top margin in points.
---@field margin_bottom? number Bottom margin in points.

---Container-level popup properties for visibility, layout, and surface styling.
---@class (exact) EasyBarPopupProps
---@field drawing? boolean Whether popup content is shown.
---@field background? EasyBarBackgroundProps Popup background styling.
---@field spacing? number Child spacing inside the popup container.
---@field width? number Popup width in points.
---@field height? number Popup height in points.
---@field opacity? number Opacity from `0` to `1`.
---@field y_offset? number Vertical offset in points.
---@field padding_x? number Horizontal popup padding shorthand.
---@field padding_y? number Vertical popup padding shorthand.
---@field paddingX? number Horizontal popup padding shorthand.
---@field paddingY? number Vertical popup padding shorthand.
---@field padding_left? number Left popup padding in points.
---@field padding_right? number Right popup padding in points.
---@field padding_top? number Top popup padding in points.
---@field padding_bottom? number Bottom popup padding in points.
---@field margin_x? number Horizontal popup margin shorthand.
---@field margin_y? number Vertical popup margin shorthand.
---@field marginX? number Horizontal popup margin shorthand.
---@field marginY? number Vertical popup margin shorthand.
---@field margin_left? number Left popup margin in points.
---@field margin_right? number Right popup margin in points.
---@field margin_top? number Top popup margin in points.
---@field margin_bottom? number Bottom popup margin in points.

---Accepted shorthand forms for label content.
---@alias EasyBarLabelLike string|number|boolean|EasyBarLabelProps

---Accepted shorthand forms for icon content.
---@alias EasyBarIconLike string|number|boolean|EasyBarIconProps

---One selectable native context-menu action.
---@class (exact) EasyBarContextMenuAction
---@field id string Action id returned as `event.action_id` when selected.
---@field title string Native menu item title.
---@field enabled? boolean Whether the action can be selected. Defaults to true.
---@field checked? boolean Whether the native checkmark is shown. Defaults to false.

---One native context-menu separator.
---@class (exact) EasyBarContextMenuSeparator
---@field separator true Marks this entry as a separator.

---One native context-menu submenu heading.
---@class (exact) EasyBarContextMenuSubmenu
---@field title string Native submenu title.
---@field submenu EasyBarContextMenuEntry[] Non-empty recursive submenu entries.

---@alias EasyBarContextMenuEntry EasyBarContextMenuAction|EasyBarContextMenuSeparator|EasyBarContextMenuSubmenu

---The main property table accepted by `easybar.add(...)` and `node:set(...)`.
---@class (exact) EasyBarNodeProps
---@field position? EasyBarPosition Root nodes use `left`, `center`, or `right`; popup children use `popup.<id>`.
---@field order? integer Render order within one bar position.
---@field drawing? boolean Whether the node is visible.
---@field parent? string Parent node id for nested layout.
---@field width? number Width in points.
---@field height? number Height in points.
---@field opacity? number Opacity from `0` to `1`.
---@field y_offset? number Vertical offset in points.
---@field interval? number Polling interval in seconds.
---@field on_interval? fun() Interval callback executed on this widget's own interval schedule.
---@field color? string Primary foreground color.
---@field icon? EasyBarIconLike Icon table or shorthand value.
---@field label? EasyBarLabelLike Label table or shorthand value.
---@field image? EasyBarImage Standalone image content.
---@field background? EasyBarBackgroundProps Background and padding styling.
---@field margin? EasyBarMarginProps Margin overrides for individual edges.
---@field popup? EasyBarPopupProps Popup container properties.
---@field context_menu? EasyBarContextMenuEntry[] Native right-click menu. Use `node:unset("context_menu")` to remove it.
---@field spacing? number Child spacing for rows, groups, and popup content.
---@field value? number Current scalar value for progress/slider nodes.
---@field min? number Minimum value for progress/slider nodes.
---@field max? number Maximum value for progress/slider nodes.
---@field step? number Slider step size.
---@field values? number[] Sparkline sample values.
---@field line_width? number Sparkline stroke width.
---@field padding_x? number Horizontal padding shorthand.
---@field padding_y? number Vertical padding shorthand.
---@field paddingX? number Horizontal padding shorthand.
---@field paddingY? number Vertical padding shorthand.
---@field margin_x? number Horizontal margin shorthand.
---@field margin_y? number Vertical margin shorthand.
---@field marginX? number Horizontal margin shorthand.
---@field marginY? number Vertical margin shorthand.
---@field margin_left? number Left margin in points.
---@field margin_right? number Right margin in points.
---@field margin_top? number Top margin in points.
---@field margin_bottom? number Bottom margin in points.

-- Generated event annotations are inserted below when producing `easybar_api.lua`.
-- The standalone generated source lives in `easybar_api.events.lua`.
-- GENERATED SECTION: easybar.events

---Namespace object exposed as `easybar.level`.
---@class EasyBarLevels
---@field trace EasyBarLevel
---@field debug EasyBarLevel
---@field info EasyBarLevel
---@field warn EasyBarLevel
---@field error EasyBarLevel

---Namespace object exposed as `easybar.kind`.
---These fields are the ergonomic way to pass node kinds to `easybar.add(...)`.
---@class EasyBarKinds
---@field item EasyBarKind Use for most ordinary widgets with icon, label, and interaction support.
---@field row EasyBarKind Use when several child nodes should be laid out horizontally.
---@field column EasyBarKind Use when several child nodes should be laid out vertically.
---@field group EasyBarKind Use when multiple child nodes should share one styled container.
---@field popup EasyBarKind Use for explicit popup container composition.
---@field slider EasyBarKind Use for interactive scalar controls.
---@field progress EasyBarKind Use for read-only scalar meters.
---@field progress_slider EasyBarKind Use when you want slider interaction with progress-style presentation.
---@field sparkline EasyBarKind Use for compact numeric trend lines.
---@field spaces EasyBarKind Use for workspace or space indicator style nodes.

---@class EasyBarNodeHandle
---@field id string Node id.
---@field set fun(self: EasyBarNodeHandle, props: EasyBarNodeProps) Merges props into this node.
---@field get fun(self: EasyBarNodeHandle): EasyBarNodeProps Returns a copy of this node's props.
---@field remove fun(self: EasyBarNodeHandle) Removes this node and all descendants.
---@field subscribe fun(self: EasyBarNodeHandle, events: EasyBarEventToken|EasyBarEventToken[], handler: EasyBarEventHandler) Subscribes this node to runtime or interaction events.

---@alias EasyBarInboxFormat
---| 'plain'
---| 'markdown'

---@alias EasyBarInboxSeverity
---| 'info'
---| 'success'
---| 'warning'
---| 'error'

---@class (exact) EasyBarInboxAction
---@field id string Action id returned to the publisher.
---@field title string Button title shown in the inbox.
---@field enabled? boolean Whether the action can be selected. Defaults to true.
---@field busy? boolean Whether the action is currently running. Defaults to false.
---@field include_in_refresh_all? boolean For source actions, includes this action in the native Refresh All command. Defaults to false.
---@field children? EasyBarInboxAction[] Nested source actions shown as a submenu. Source actions support up to three levels; item actions cannot have children.

---@class (exact) EasyBarInboxSourcePresentation
---@field name? string Display name. Defaults to the publisher source.
---@field icon? string Optional icon text or image path returned by `easybar.asset(...)`.
---@field color? string Optional source accent color. Accepts theme tokens or hex colors.
---@field order? integer Optional ascending order when inbox items are grouped by source. Explicit orders appear before unordered sources.

---@class (exact) EasyBarInboxItem
---@field id string Stable id within the source snapshot.
---@field title string Message title.
---@field body? string Optional plain text or limited inline Markdown body.
---@field format? EasyBarInboxFormat Body format. Defaults to plain.
---@field timestamp? number Unix timestamp used for sorting and date grouping.
---@field category? string Optional category used for grouping.
---@field severity? EasyBarInboxSeverity Message severity. Defaults to info.
---@field unread? boolean Initial unread state. Defaults to true.
---@field dismissible? boolean Whether local dismiss actions are available. Defaults to true.
---@field actions? EasyBarInboxAction[] Actions routed back through `on_action`.
---@field source? EasyBarInboxSourcePresentation Optional source presentation metadata.
---@field url? string Optional HTTP(S) URL shown as an Open action.

---@class EasyBarInboxActionEvent
---@field name 'inbox.action'
---@field source string Publisher source.
---@field target_widget_id string Inbox item id.
---@field action_id string Selected action id.

---@class (exact) EasyBarInboxConfiguration
---@field actions? EasyBarInboxAction[] Actions shown under this source in the inbox context menu. Actions with children become submenus.
---@field order? integer Optional ascending source order in the inbox context menu. Explicit orders appear before unordered sources.
---@field presentation? EasyBarInboxSourcePresentation Optional source presentation retained even when the source has no current items.

---@class EasyBarInboxContextActionEvent
---@field name 'inbox.context_action'
---@field source string Publisher source.
---@field action_id string Selected source action id.

---@class EasyBarInbox
local EasyBarInbox = {}

---Atomically replaces every current inbox item for one source.
---@param source string Stable publisher name used for grouping and action routing.
---@param items EasyBarInboxItem[] Complete current snapshot for this source.
function EasyBarInbox.replace(source, items) end

---Clears every current inbox item for one source.
---@param source string Publisher name previously used with `replace(...)`.
function EasyBarInbox.clear(source) end

---Configures source-owned actions shown in the inbox popup header.
---@param source string Stable publisher name used for context-action routing.
---@param configuration EasyBarInboxConfiguration Source-level action configuration.
function EasyBarInbox.configure(source, configuration) end

---Registers an action handler for one source.
---@param source string Publisher name whose item actions should be delivered.
---@param handler fun(event:EasyBarInboxActionEvent) Callback invoked for matching item actions and native `mark_read` transitions.
---@return EasyBarSubscriptionHandle subscription Disposable registration handle.
function EasyBarInbox.on_action(source, handler) end

---Registers a source context-menu action handler.
---@param source string Publisher name whose source actions should be delivered.
---@param handler fun(event:EasyBarInboxContextActionEvent) Callback invoked for matching source actions.
---@return EasyBarSubscriptionHandle subscription Disposable registration handle.
function EasyBarInbox.on_context_action(source, handler) end

---Values supported by widget config storage.
---@alias EasyBarStorageValue string|boolean|number|string[]

---Widget settings persisted below `[widgets.<widget>]` in `config.toml`.
---@class EasyBarStorage
local EasyBarStorage = {}

---Reads one widget setting from `config.toml`.
---@param widget string Widget namespace below `[widgets]`; letters, numbers, underscores, and hyphens are accepted.
---@param key string Setting key; letters, numbers, underscores, and hyphens are accepted.
---@param default? EasyBarStorageValue Value returned when the setting does not exist.
---@return EasyBarStorageValue|nil value Stored value, `default`, or `nil` when absent.
function EasyBarStorage.get(widget, key, default) end

---Persists one widget setting in `config.toml`.
---@param widget string Widget namespace below `[widgets]`; letters, numbers, underscores, and hyphens are accepted.
---@param key string Setting key; letters, numbers, underscores, and hyphens are accepted.
---@param value EasyBarStorageValue String, boolean, finite number, or dense string array to persist.
---@return boolean ok Whether the config was updated.
---@return string? error_message Failure detail when `ok` is `false`.
function EasyBarStorage.set(widget, key, value) end

---@class EasyBarJsonNull

---@class EasyBarJson
---@field null EasyBarJsonNull Sentinel used for decoded JSON null values.
---@field array fun(value?: table): table Marks a table as a JSON array, including an empty table.
---@field object fun(value?: table): table Marks a table as a JSON object, including an empty table.
---@field is_array fun(value: any): boolean Returns whether a value is a dense JSON-array table.
---@field encode fun(value: any): string Encodes one Lua value tree into a JSON string.
---@field decode fun(text: string): any Decodes one JSON string while preserving null and container shapes.

-- GENERATED SECTION: easybar.themes
-- EasyBar generated theme stub. Do not edit by hand.
-- Source of truth: Sources/EasyBarKit/Theme/theme_tokens.json
-- Regenerate with: scripts/generate/theme_tokens.py
---Resolved active theme colors.
---@class EasyBarThemeColors
---@field background string Main bar and popup background color.
---@field surface string Normal widget or inactive surface color.
---@field surface_elevated string Focused, active, or raised surface color.
---@field surface_hover string Hover or highlighted surface color.
---@field text string Primary text color.
---@field text_secondary string Secondary body or label text color.
---@field text_tertiary string Tertiary text color for quieter labels.
---@field muted string Secondary, inactive, or unavailable text color.
---@field muted_secondary string Secondary muted tone for softer supporting content.
---@field outside_month string Calendar text color for days outside the active month.
---@field accent string Accent color.
---@field accent_secondary string Secondary accent color for supporting highlights.
---@field accent_soft string Softer accent color for subtle emphasis.
---@field success string Positive or healthy status color.
---@field success_secondary string Secondary positive color for supporting signals.
---@field warning string Warning status color.
---@field orange string Orange status color for low or degraded states.
---@field error string Error or critical status color.
---@field danger string Strong danger color for urgent attention.
---@field border string Normal border color.
---@field border_strong string Emphasized border color.
---@field border_subtle string Subtle or transparent border color.
---@field selection_text string Text color drawn on top of selected surfaces.
---@field selection_background string Background color used for selected surfaces.
---@field transparent string Fully transparent color.
---@field overlay_outline string Overlay outline color with alpha.
---@field overlay_text string High-contrast overlay glyph or text color.

---Theme reference strings accepted by color fields.
---These always mirror the active `EasyBarThemeColors` keys.
---@class EasyBarThemeRefs
---@field background string Reference string for `theme.background`.
---@field surface string Reference string for `theme.surface`.
---@field surface_elevated string Reference string for `theme.surface_elevated`.
---@field surface_hover string Reference string for `theme.surface_hover`.
---@field text string Reference string for `theme.text`.
---@field text_secondary string Reference string for `theme.text_secondary`.
---@field text_tertiary string Reference string for `theme.text_tertiary`.
---@field muted string Reference string for `theme.muted`.
---@field muted_secondary string Reference string for `theme.muted_secondary`.
---@field outside_month string Reference string for `theme.outside_month`.
---@field accent string Reference string for `theme.accent`.
---@field accent_secondary string Reference string for `theme.accent_secondary`.
---@field accent_soft string Reference string for `theme.accent_soft`.
---@field success string Reference string for `theme.success`.
---@field success_secondary string Reference string for `theme.success_secondary`.
---@field warning string Reference string for `theme.warning`.
---@field orange string Reference string for `theme.orange`.
---@field error string Reference string for `theme.error`.
---@field danger string Reference string for `theme.danger`.
---@field border string Reference string for `theme.border`.
---@field border_strong string Reference string for `theme.border_strong`.
---@field border_subtle string Reference string for `theme.border_subtle`.
---@field selection_text string Reference string for `theme.selection_text`.
---@field selection_background string Reference string for `theme.selection_background`.
---@field transparent string Reference string for `theme.transparent`.
---@field overlay_outline string Reference string for `theme.overlay_outline`.
---@field overlay_text string Reference string for `theme.overlay_text`.

---Active resolved theme exposed to Lua widgets.
---Use `theme.colors.<token>` for resolved hex colors and `theme.ref.<token>` when you want to keep a node color bound to the active theme.
---@class EasyBarTheme
---@field name string Active theme name from `[theme].name`.
---@field colors EasyBarThemeColors Resolved theme colors.
---@field ref EasyBarThemeRefs Theme reference strings such as `theme.text`.
-- END GENERATED SECTION: easybar.themes

---Per-call execution and diagnostic options for `easybar.exec(...)`, `easybar.exec_async(...)`, and `easybar.spawn_async(...)`.
---Omitted execution-limit fields use the current `[app.lua_commands]` defaults.
---@class (exact) EasyBarCommandOptions
---@field timeout_seconds? number Hard timeout in seconds. Must be greater than zero.
---@field max_output_bytes? integer Maximum combined stdout and stderr bytes. Must be a positive integer.
---@field raw_output? boolean Preserve output exactly, including trailing line endings. Defaults to false.
---@field log_operation? string Optional human-readable operation name attached to command diagnostics.

---Metadata supplied with one completed EasyBar command.
---@class (exact) EasyBarCommandMetadata
---@field duration_ms integer Host-measured command duration in milliseconds.

---Opaque token identifying one asynchronous command in the current Lua runtime session.
---Do not persist tokens across config reloads or application restarts.
---@alias EasyBarAsyncToken string

---Exit status returned by EasyBar command APIs.
---Normal process exit codes are preserved. EasyBar uses `124` for timeout, `65` for output-limit
---termination, `127` when an executable cannot be found, and `130` after cancellation.
---@alias EasyBarCommandExitCode integer

---Completion callback for asynchronous command APIs.
---It runs exactly once with combined stdout and stderr after the process exits or is terminated.
---@alias EasyBarCommandCallback fun(output:string, code:EasyBarCommandExitCode, metadata:EasyBarCommandMetadata)

---One-shot callback scheduled by `easybar.after(...)`.
---@alias EasyBarTimerCallback fun()

---Options for `easybar.log.with_file(...)`.
---@class EasyBarLogFileOptions
---@field prefix? string Optional prefix added to host log lines and file-backed logger lines.

---Callable widget logger returned by `easybar.log.with_prefix(...)`.
---@class EasyBarPrefixedLogger
---@overload fun(level: EasyBarLevel|string, ...: any)
---@diagnostic disable-next-line: unused-local
local EasyBarPrefixedLogger = {}

---File-backed widget logger returned by `easybar.log.with_file(...)`.
---@class EasyBarFileLogger
---@field append fun(text: any): boolean, string? Appends raw text to the widget log file and adds a trailing newline when missing.
---@field line fun(text: any): boolean, string? Appends one line to the widget log file.
---@field tail fun(limit: integer): string Returns the newest log lines as one newline-delimited string.
---@field trim fun(limit: integer): boolean, string? Keeps only the newest log lines in the widget log file.
---@overload fun(level: EasyBarLevel|string, ...: any): boolean, string?
local EasyBarFileLogger = {}

---Callable widget logger exposed as `easybar.log`.
---@class EasyBarLogFunction
---@field with_prefix fun(prefix: string): EasyBarPrefixedLogger Creates a widget logger that prepends a stable prefix to normal EasyBar host logs.
---@field with_file fun(file_name: string, options?: EasyBarLogFileOptions): EasyBarFileLogger Creates a widget logger that writes normal EasyBar logs and appends to a file in `easybar.log_dir`.
---@overload fun(level: EasyBarLevel|string, ...: any)
---@diagnostic disable-next-line: unused-local
local EasyBarLogFunction = {}

---Widget-scoped EasyBar API injected into every widget file.
---Use it to create nodes, run commands, and write widget logs.
---@class EasyBar
---@field DEFAULT_EXEC_OPTIONS EasyBarCommandOptions Read-only table exposing the current host default command limits.
---@field version string EasyBar application version (`__EASYBAR_VERSION__`).
---@field add fun(kind: EasyBarKind, id: string, props?: EasyBarNodeProps): EasyBarNodeHandle Creates one node and returns its handle.
---@field asset fun(path: string): string Resolves a path relative to the current widget file, or from the widgets root with `@/`.
---@field clear_defaults fun() Clears widget-local defaults previously set with `easybar.default(...)`.
---@field default fun(props: EasyBarNodeProps) Sets widget-local default props for future `easybar.add(...)` calls.
---@field events EasyBarEvents Event token namespace used by `node:subscribe(...)`, plus mouse constants.
---@field exec fun(command: string, options?: EasyBarCommandOptions): string, EasyBarCommandExitCode Runs one shell command synchronously and returns combined output plus exit status.
---@field exec_async fun(command: string, options: EasyBarCommandOptions|nil, callback: EasyBarCommandCallback): EasyBarAsyncToken Runs one shell command asynchronously.
---@field spawn_async fun(arguments: string[], options: EasyBarCommandOptions|nil, callback: EasyBarCommandCallback): EasyBarAsyncToken Runs one executable asynchronously without shell parsing.
---@field cancel_async fun(token: EasyBarAsyncToken): boolean Requests cancellation of one pending asynchronous command.
---@field after fun(delay_seconds: number, callback: EasyBarTimerCallback): EasyBarTimerHandle Schedules one cancellable, non-blocking callback.
---@field get fun(id: string): EasyBarNodeProps Returns a copy of one node's props by id.
---@field json EasyBarJson JSON helper namespace for widget-side encoding and decoding.
---@field kind EasyBarKinds Kind constants used by `easybar.add(...)`.
---@field level EasyBarLevels Log level namespace used by `easybar.log(...)`.
---@field log EasyBarLogFunction Callable widget logger. Use `easybar.log(level, ...)` for host logs, `easybar.log.with_prefix(...)` for prefixed host logs, or `easybar.log.with_file(...)` for file-backed widget logs.
---@field log_dir string Configured EasyBar logging directory from `[logging].directory`.
---@field remove fun(id: string) Removes one node and all descendants by id.
---@field set fun(id: string, props: EasyBarNodeProps) Merges props into one node by id.
---@field unset fun(id: string, paths: string|string[]) Removes one or more nested property paths from one node by id.
---@field subscribe fun(id: string, events: EasyBarEventToken|EasyBarEventToken[], handler: EasyBarEventHandler): EasyBarSubscriptionHandle Subscribes one node by id and returns a disposable handle.
---@field theme EasyBarTheme Active resolved theme.
---@field inbox EasyBarInbox Shared native inbox publishing API.
---@field storage EasyBarStorage Widget settings backed by the reserved `[widgets]` config namespace.
local EasyBar = {}

---Resolves a path relative to the current widget file, or from the widgets root with `@/`.
---@param path string Relative asset path. Prefix with `@/` to resolve from the configured widgets directory.
---@return string resolved_path Safe filesystem path resolved from the selected asset root.
function EasyBar.asset(path) end

---@class EasyBarNodeHandle
local EasyBarNodeHandle = {}

---Disposable event subscription returned by `node:subscribe(...)` and `easybar.subscribe(...)`.
---@class EasyBarSubscriptionHandle
local EasyBarSubscriptionHandle = {}

---Removes this subscription. Repeated calls return false.
---@return boolean removed Whether an active registration was removed.
function EasyBarSubscriptionHandle:unsubscribe() end

---Cancellable one-shot timer returned by `easybar.after(...)`.
---The handle belongs to the current Lua runtime session and becomes inactive after firing or cancellation.
---@class (exact) EasyBarTimerHandle
---@field token string Opaque host timer token. Do not persist or modify it.
local EasyBarTimerHandle = {}

---Cancels this timer if its callback has not fired yet.
---@return boolean cancelled `true` when a pending callback was cancelled; otherwise `false`.
function EasyBarTimerHandle:cancel() end

---Merges properties into this node.
---@param props EasyBarNodeProps Properties to merge; unspecified properties remain unchanged.
function EasyBarNodeHandle:set(props) end

---Returns a copy of this node's current property table.
---@return EasyBarNodeProps props Snapshot safe to inspect or modify locally.
function EasyBarNodeHandle:get() end

---Removes this node and all of its descendants.
function EasyBarNodeHandle:remove() end

---Removes one or more nested properties from this node.
---@param paths string|string[] Dot-separated property path or array of paths to remove.
function EasyBarNodeHandle:unset(paths) end

---Subscribes this node to one or more event tokens.
---Interaction belongs to this node frame.
---@param events EasyBarEventToken|EasyBarEventToken[] One event token or an array of tokens.
---@param handler EasyBarEventHandler Callback invoked when one subscribed event is delivered.
---@return EasyBarSubscriptionHandle subscription Disposable registration handle.
function EasyBarNodeHandle:subscribe(events, handler) end

---Sets per-widget default properties for future `easybar.add(...)` calls.
---Defaults apply only within the current widget file.
---@param props EasyBarNodeProps Defaults merged into future nodes created by this widget file.
function EasyBar.default(props) end

---Clears previously configured widget defaults.
function EasyBar.clear_defaults() end

---Merges properties into one existing node by id.
---@param id string Existing node id in the current widget runtime.
---@param props EasyBarNodeProps Properties to merge; unspecified properties remain unchanged.
function EasyBar.set(id, props) end

---Removes one or more nested properties from one existing node by id.
---@param id string Existing node id in the current widget runtime.
---@param paths string|string[] Dot-separated property path or array of paths to remove.
function EasyBar.unset(id, paths) end

---Returns a copy of one existing node's current property table.
---@param id string Existing node id in the current widget runtime.
---@return EasyBarNodeProps props Snapshot safe to inspect or modify locally.
function EasyBar.get(id) end

---Removes one existing node and all of its descendants by id.
---@param id string Existing node id in the current widget runtime.
function EasyBar.remove(id) end

---Subscribes one existing node to one or more event tokens by id.
---@param id string Existing node id in the current widget runtime.
---@param events EasyBarEventToken|EasyBarEventToken[] One event token or an array of tokens.
---@param handler EasyBarEventHandler Callback invoked when one subscribed event is delivered.
---@return EasyBarSubscriptionHandle subscription Disposable registration handle.
function EasyBar.subscribe(id, events, handler) end

---Creates one EasyBar node and returns its handle.
---Use `easybar.kind.item` for simple widgets, `easybar.kind.group` for shared containers,
---and `easybar.kind.row` / `easybar.kind.column` for layout wrappers around child nodes.
---When `interval` and `on_interval` are provided, EasyBar runs `on_interval`
---on this widget's own repeating schedule without requiring an event subscription.
---@param kind EasyBarKind Node kind, normally selected from `easybar.kind`.
---@param id string Widget-unique node id used for updates, events, and parent references.
---@param props? EasyBarNodeProps Initial node properties merged with widget-local defaults.
---@return EasyBarNodeHandle node Handle for local updates, subscriptions, and removal.
function EasyBar.add(kind, id, props) end

---Runs one shell command synchronously through `/bin/sh -lc`.
---This blocks the Lua runtime until completion, so prefer it only for short, local commands.
---Output combines stdout and stderr. Trailing line endings are removed unless `raw_output = true`.
---@param command string Shell source passed to `/bin/sh -lc`.
---@param options? EasyBarCommandOptions Optional per-call limits; omitted fields use host defaults.
---@return string output Combined stdout and stderr, optionally preserved exactly with `raw_output`.
---@return EasyBarCommandExitCode code Process exit status or an EasyBar termination status.
function EasyBar.exec(command, options) end

---Runs one shell command asynchronously through `/bin/sh -lc`.
---Use this only when shell syntax such as pipes, redirection, expansion, or compound commands is required.
---The callback runs exactly once after normal exit, timeout, output-limit termination, launch failure, or cancellation.
---@param command string Shell source passed to `/bin/sh -lc`.
---@param options EasyBarCommandOptions|nil Optional per-call execution and diagnostic options, or `nil` to use host defaults.
---@param callback EasyBarCommandCallback Receives combined output, final exit status, and duration metadata.
---@return EasyBarAsyncToken token Token accepted by `easybar.cancel_async(...)` while the command is pending.
function EasyBar.exec_async(command, options, callback) end

---Runs one executable asynchronously without shell parsing or interpolation.
---The first array element is the executable; remaining elements are passed exactly as process arguments.
---Prefer this over `easybar.exec_async(...)` whenever shell behavior is not required.
---@param arguments string[] Dense argument array whose first element is an executable name or path.
---@param options EasyBarCommandOptions|nil Optional per-call execution and diagnostic options, or `nil` to use host defaults.
---@param callback EasyBarCommandCallback Receives combined output, final exit status, and duration metadata.
---@return EasyBarAsyncToken token Token accepted by `easybar.cancel_async(...)` while the command is pending.
function EasyBar.spawn_async(arguments, options, callback) end

---Schedules one non-blocking, one-shot callback using a host-owned timer.
---The delay must be finite and non-negative. A zero delay schedules the callback asynchronously;
---it does not run inline before `easybar.after(...)` returns.
---@param delay_seconds number Minimum delay in seconds before the callback becomes eligible to run.
---@param callback EasyBarTimerCallback Callback invoked at most once unless cancelled first.
---@return EasyBarTimerHandle timer Handle used to cancel the pending callback.
function EasyBar.after(delay_seconds, callback) end

---Requests cancellation of one pending asynchronous command and its process group.
---This function returns immediately. When cancellation succeeds, the original command callback runs
---after termination with exit status `130` and any output captured before the process stopped.
---@param token EasyBarAsyncToken Token returned by `easybar.exec_async(...)` or `easybar.spawn_async(...)`.
---@return boolean pending `true` when the token was still pending and cancellation was requested; otherwise `false`.
function EasyBar.cancel_async(token) end

---EasyBar application version (`__EASYBAR_VERSION__`).
---@type string
EasyBar.version = "__EASYBAR_VERSION__"

---Read-only table exposing the current host default command limits.
---@type EasyBarCommandOptions
EasyBar.DEFAULT_EXEC_OPTIONS = {}

---All supported EasyBar event tokens and mouse constants.
---@type EasyBarEvents
EasyBar.events = {}

---Configured EasyBar logging directory from `[logging].directory`.
---@type string
EasyBar.log_dir = ""

---Shared native inbox publishing API.
---@type EasyBarInbox
EasyBar.inbox = {}

---Widget settings backed by the reserved `[widgets]` config namespace.
---@type EasyBarStorage
EasyBar.storage = {}

---Writes one widget-scoped log line to the EasyBar host logger.
---Supported levels are `trace`, `debug`, `info`, `warn`, and `error`.
---Which messages are emitted depends on the persistent host level and active live log subscriptions.
---@param level EasyBarLevel|string Minimum severity for this message.
---@param ... any Values converted to text and joined into one log message.
---@diagnostic disable-next-line: assign-type-mismatch
function EasyBar.log(level, ...) end

---Creates a widget logger that prepends a stable prefix to normal EasyBar host logs.
---@param prefix string Prefix added to every message from the returned logger.
---@return EasyBarPrefixedLogger logger Callable prefixed host logger.
function EasyBar.log.with_prefix(prefix) end

---Creates a widget logger that writes normal EasyBar logs and appends to a file in `easybar.log_dir`.
---The file name must be a plain file name, not a path.
---@param file_name string Plain file name created inside `easybar.log_dir`; paths are rejected.
---@param options? EasyBarLogFileOptions Optional line prefix configuration.
---@return EasyBarFileLogger logger Callable host-and-file logger with file utility methods.
function EasyBar.log.with_file(file_name, options) end

---Appends raw text to the widget log file and adds a trailing newline when missing.
---@param text any Value appended as text; one trailing newline is added when missing.
---@return boolean ok Whether the write succeeded.
---@return string? error_message Failure detail when `ok` is `false`.
function EasyBarFileLogger.append(text) end

---Appends one line to the widget log file.
---@param text any Value appended as exactly one logical line.
---@return boolean ok Whether the write succeeded.
---@return string? error_message Failure detail when `ok` is `false`.
function EasyBarFileLogger.line(text) end

---Returns the newest log lines as one newline-delimited string.
---@param limit integer Maximum number of newest lines to return.
---@return string text Newline-delimited tail content, or an empty string when unavailable.
function EasyBarFileLogger.tail(limit) end

---Keeps only the newest log lines in the widget log file.
---@param limit integer Number of newest lines to retain.
---@return boolean ok Whether the trim succeeded.
---@return string? error_message Failure detail when `ok` is `false`.
function EasyBarFileLogger.trim(limit) end

---@type EasyBar
easybar = easybar

return easybar
