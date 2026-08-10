--- Module contract:
--- Owns render-time style normalization, shared defaults, and node construction.
--- Returns helpers consumed by the tree builder and flattener.
local M = {}

local helpers = require("easybar.helpers")

local DEFAULT_ROOT_SHELL_STYLE = {
	background = {
		color = "#1a1a1a",
		border_color = "#333333",
		border_width = 1,
		corner_radius = 8,
		padding_left = 8,
		padding_right = 8,
		padding_top = 4,
		padding_bottom = 4,
	},
}

local DEFAULT_POPUP_TEXT_COLOR = "#cdd6f4"
local DEFAULT_POPUP_STYLE = {
	background = {
		color = "#111111",
		border_color = "#444444",
		border_width = 1,
		corner_radius = 8,
	},
	padding_x = 8,
	padding_y = 6,
	margin_x = 0,
	margin_y = 8,
	spacing = 4,
}

--- Recursively merges one style table into another.
local function deep_merge(target, source)
	if type(source) ~= "table" then
		return target
	end

	for key, value in pairs(source) do
		if type(value) == "table" and type(target[key]) == "table" then
			deep_merge(target[key], value)
		else
			target[key] = helpers.deep_copy(value)
		end
	end

	return target
end

--- Normalizes a bar position to a supported host value.
function M.normalize_position(position)
	if position == "left" or position == "center" or position == "right" then
		return position
	end

	return "right"
end

--- Extracts display text from scalar or structured label props.
local function label_string(label)
	if type(label) == "table" then
		return label.string or ""
	end

	if type(label) == "string" then
		return label
	end

	return ""
end

--- Extracts display text from scalar or structured icon props.
local function icon_string(icon)
	if type(icon) == "table" then
		return icon.string or ""
	end

	if type(icon) == "string" then
		return icon
	end

	return ""
end

--- Resolves the primary item color from label, icon, or root props.
local function resolve_color(props)
	if props.color ~= nil then
		return props.color
	end

	if type(props.label) == "table" and props.label.color ~= nil then
		return props.label.color
	end

	if type(props.icon) == "table" and props.icon.color ~= nil then
		return props.icon.color
	end

	return ""
end

--- Resolves a label-specific color override.
local function resolve_label_color(props)
	if type(props.label) == "table" then
		return props.label.color
	end

	return nil
end

--- Resolves an icon-specific color override.
local function resolve_icon_color(props)
	if type(props.icon) == "table" then
		return props.icon.color
	end

	return nil
end

--- Resolves a label font-size override from structured props.
local function resolve_label_font_size(props)
	if type(props.label) == "table" and type(props.label.font) == "table" then
		return tonumber(props.label.font.size)
	end

	return nil
end

--- Resolves an icon font-size override from structured props.
local function resolve_icon_font_size(props)
	if type(props.icon) == "table" and type(props.icon.font) == "table" then
		return tonumber(props.icon.font.size)
	end

	return nil
end

--- Resolves a horizontal icon offset from structured props.
local function resolve_icon_offset_x(props)
	if type(props.icon) == "table" then
		return tonumber(props.icon.offset_x)
	end

	return nil
end

--- Resolves a vertical icon offset from structured props.
local function resolve_icon_offset_y(props)
	if type(props.icon) == "table" then
		return tonumber(props.icon.offset_y)
	end

	return nil
end

--- Selects the structured icon image property table.
local function resolve_image_props(props)
	if type(props.icon) == "table" and type(props.icon.image) == "table" then
		return props.icon.image
	end

	return nil
end

--- Resolves a file-backed image path when configured.
local function resolve_image_path(props)
	local image = resolve_image_props(props)
	return type(image) == "table" and image.path or nil
end

--- Resolves inline SVG image content when configured.
local function resolve_image_svg(props)
	local image = resolve_image_props(props)
	return type(image) == "table" and image.svg or nil
end

--- Resolves image size from structured image properties.
local function resolve_image_size(props)
	local image = resolve_image_props(props)
	if type(image) == "table" and image.size ~= nil then
		return tonumber(image.size)
	end

	return nil
end

--- Resolves image corner radius from structured image properties.
local function resolve_image_corner_radius(props)
	local image = resolve_image_props(props)
	if type(image) == "table" and image.corner_radius ~= nil then
		return tonumber(image.corner_radius)
	end

	return nil
end

--- Resolves node spacing.
local function resolve_spacing(props)
	if props.spacing ~= nil then
		return tonumber(props.spacing)
	end

	return nil
end

--- Resolves one box-model value from flat and nested property forms.
local function resolve_box_value(props, key, box)
	if props[key] ~= nil then
		return tonumber(props[key])
	end

	if type(props[box]) == "table" and props[box][key] ~= nil then
		return tonumber(props[box][key])
	end

	return nil
end

--- Resolves whether a node participates in drawing.
local function resolve_drawing(props, default)
	if props.drawing == nil then
		return default
	end

	return props.drawing ~= false
end

--- Returns the explicit popup parent id declared by one item.
function M.popup_parent_id(item)
	local position = item.props.position

	if type(position) == "string" then
		return position:match("^popup%.(.+)$")
	end

	return nil
end

--- Returns the explicit regular parent id declared by one item.
function M.regular_parent_id(item)
	if type(item.props.parent) == "string" and item.props.parent ~= "" then
		return item.props.parent
	end

	return nil
end

--- Returns whether an item is attached inside a popup hierarchy.
local function is_popup_item(item)
	return M.popup_parent_id(item) ~= nil
end

--- Returns whether an item is a top-level bar root.
local function is_bar_root_item(item)
	return M.regular_parent_id(item) == nil and M.popup_parent_id(item) == nil
end

--- Returns whether a root receives the default layout and background shell.
local function uses_default_root_shell(item)
	return is_bar_root_item(item) and item.kind ~= "popup"
end

--- Creates the shared host node fields used by every rendered kind.
local function base_node(id, kind, root_position, order, visible)
	return {
		id = id,
		kind = kind,
		position = M.normalize_position(root_position),
		order = tonumber(order or 0) or 0,
		visible = visible ~= false,
		receivesMouseHover = false,
		receivesMouseDown = false,
		receivesMouseUp = false,
		receivesMouseClick = false,
		receivesMouseScroll = false,
	}
end

--- Applies padding, border, background, and geometry props to a host node.
local function apply_box_style(node, props)
	node.paddingX = tonumber(props.padding_x or props.paddingX)
	node.paddingY = tonumber(props.padding_y or props.paddingY)
	node.paddingLeft = resolve_box_value(props, "padding_left", "background")
	node.paddingRight = resolve_box_value(props, "padding_right", "background")
	node.paddingTop = resolve_box_value(props, "padding_top", "background")
	node.paddingBottom = resolve_box_value(props, "padding_bottom", "background")
	node.marginX = tonumber(props.margin_x or props.marginX)
	node.marginY = tonumber(props.margin_y or props.marginY)
	node.marginLeft = resolve_box_value(props, "margin_left", "margin")
	node.marginRight = resolve_box_value(props, "margin_right", "margin")
	node.marginTop = resolve_box_value(props, "margin_top", "margin")
	node.marginBottom = resolve_box_value(props, "margin_bottom", "margin")
	node.spacing = resolve_spacing(props)
	node.backgroundColor = type(props.background) == "table" and props.background.color or props.backgroundColor
	node.borderColor = type(props.background) == "table" and props.background.border_color or props.borderColor
	node.borderWidth = type(props.background) == "table" and tonumber(props.background.border_width)
		or tonumber(props.borderWidth)
	node.cornerRadius = type(props.background) == "table" and tonumber(props.background.corner_radius)
		or tonumber(props.cornerRadius)
	node.opacity = tonumber(props.opacity)
	node.width = tonumber(props.width)
	node.height = tonumber(props.height)
	node.yOffset = tonumber(props.y_offset)
	return node
end

--- Applies validated interaction and context-menu metadata to a host node.
local function apply_interaction(node, interaction)
	node.receivesMouseHover = interaction.hover
	node.receivesMouseDown = interaction.down
	node.receivesMouseUp = interaction.up
	node.receivesMouseClick = interaction.click
	node.receivesMouseScroll = interaction.scroll
	return node
end

--- Resolves mouse event requirements from active subscriptions for one node.
local function resolve_mouse_interaction(registry, id)
	local subscriptions = registry._state.subscriptions[id]
	if type(subscriptions) ~= "table" then
		return {
			hover = false,
			down = false,
			up = false,
			click = false,
			scroll = false,
		}
	end

	local hover = false
	local down = false
	local up = false
	local click = false
	local scroll = false

	for event_name in pairs(subscriptions) do
		if type(event_name) == "string" then
			if event_name == "mouse.entered" or event_name == "mouse.exited" then
				hover = true
			elseif event_name == "mouse.down" then
				down = true
			elseif event_name == "mouse.up" then
				up = true
			elseif event_name == "mouse.clicked" then
				click = true
			elseif event_name == "mouse.scrolled" then
				scroll = true
			end
		end
	end

	return {
		hover = hover,
		down = down,
		up = up,
		click = click,
		scroll = scroll,
	}
end

--- Converts one registry item into a fully styled host render node.
function M.make_node(registry, id, item, root_position, children)
	local props = item.props
	local resolved_props = props
	local kind = item.kind or "item"

	if kind == "item" and type(children) == "table" and #children > 0 then
		kind = "row"
	end

	if uses_default_root_shell(item) then
		resolved_props = {}
		deep_merge(resolved_props, DEFAULT_ROOT_SHELL_STYLE)
		deep_merge(resolved_props, props)
	end

	local node = base_node(id, kind, root_position, resolved_props.order, resolve_drawing(resolved_props, true))
	node.icon = icon_string(resolved_props.icon)
	node.text = label_string(resolved_props.label)
	node.color = resolve_color(resolved_props)
	node.iconColor = resolve_icon_color(resolved_props)
	node.labelColor = resolve_label_color(resolved_props)
	node.imagePath = resolve_image_path(resolved_props)
	node.imageSVG = resolve_image_svg(resolved_props)
	node.imageSize = resolve_image_size(resolved_props)
	node.imageCornerRadius = resolve_image_corner_radius(resolved_props)
	node.iconFontSize = resolve_icon_font_size(resolved_props)
	node.labelFontSize = resolve_label_font_size(resolved_props)
	node.iconOffsetX = resolve_icon_offset_x(resolved_props)
	node.iconOffsetY = resolve_icon_offset_y(resolved_props)
	node.value = tonumber(resolved_props.value)
	node.min = tonumber(resolved_props.min)
	node.max = tonumber(resolved_props.max)
	node.step = tonumber(resolved_props.step)
	node.values = resolved_props.values
	node.lineWidth = tonumber(resolved_props.line_width or resolved_props.lineWidth)
	node.children = children
	node.contextMenu = resolved_props.context_menu

	if is_popup_item(item) and node.color == "" then
		node.color = DEFAULT_POPUP_TEXT_COLOR
	end

	return apply_interaction(apply_box_style(node, resolved_props), resolve_mouse_interaction(registry, id))
end

--- Builds the renderer-owned container wrapping one item's popup children.
function M.make_popup_container(id, root_position, popup_props, children)
	local resolved_popup_props = {}
	deep_merge(resolved_popup_props, DEFAULT_POPUP_STYLE)
	deep_merge(resolved_popup_props, popup_props or {})

	local node = base_node(id, "column", root_position, 0, resolve_drawing(resolved_popup_props, false))
	node.icon = ""
	node.text = ""
	node.color = ""
	node.children = children
	return apply_box_style(node, resolved_popup_props)
end

return M
