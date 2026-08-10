--- Module contract:
--- Owns flattening nested render trees into the node payload expected by Swift.
--- Returns one helper that appends flattened nodes into an output array.
local M = {}

local style = require("easybar.render.style")

--- Preserves enabled flags while omitting false values from host payloads.
local function true_or_nil(value)
	if value == true then
		return true
	end

	return nil
end

--- Flattens one nested renderer node tree into host protocol node records.
function M.flatten_node(node, root_id, parent_id, inherited_position, out)
	local id = node.id or (root_id .. "_" .. tostring(#out + 1))
	local position = style.normalize_position(node.position or inherited_position or "right")

	out[#out + 1] = {
		id = id,
		root = root_id,
		kind = node.kind or "item",
		parent = parent_id,
		position = position,
		order = tonumber(node.order or 0) or 0,
		role = node.role,
		icon = node.icon or "",
		text = node.text or "",
		color = node.color or "",
		iconColor = node.iconColor,
		labelColor = node.labelColor,
		image_path = node.imagePath,
		image_svg = node.imageSVG,
		imageSize = tonumber(node.imageSize),
		imageCornerRadius = tonumber(node.imageCornerRadius),
		iconFontSize = tonumber(node.iconFontSize),
		labelFontSize = tonumber(node.labelFontSize),
		iconOffsetX = tonumber(node.iconOffsetX),
		iconOffsetY = tonumber(node.iconOffsetY),
		visible = node.visible ~= false,
		receivesMouseHover = true_or_nil(node.receivesMouseHover),
		receivesMouseDown = true_or_nil(node.receivesMouseDown),
		receivesMouseUp = true_or_nil(node.receivesMouseUp),
		receivesMouseClick = true_or_nil(node.receivesMouseClick),
		receivesMouseScroll = true_or_nil(node.receivesMouseScroll),
		context_menu = node.contextMenu,
		value = tonumber(node.value),
		min = tonumber(node.min),
		max = tonumber(node.max),
		step = tonumber(node.step),
		values = node.values,
		lineWidth = tonumber(node.lineWidth),
		paddingX = tonumber(node.paddingX),
		paddingY = tonumber(node.paddingY),
		paddingLeft = tonumber(node.paddingLeft),
		paddingRight = tonumber(node.paddingRight),
		paddingTop = tonumber(node.paddingTop),
		paddingBottom = tonumber(node.paddingBottom),
		marginX = tonumber(node.marginX),
		marginY = tonumber(node.marginY),
		marginLeft = tonumber(node.marginLeft),
		marginRight = tonumber(node.marginRight),
		marginTop = tonumber(node.marginTop),
		marginBottom = tonumber(node.marginBottom),
		spacing = tonumber(node.spacing),
		backgroundColor = node.backgroundColor,
		borderColor = node.borderColor,
		borderWidth = tonumber(node.borderWidth),
		cornerRadius = tonumber(node.cornerRadius),
		opacity = tonumber(node.opacity),
		width = tonumber(node.width),
		height = tonumber(node.height),
		yOffset = tonumber(node.yOffset),
	}

	if type(node.children) == "table" then
		for _, child in ipairs(node.children) do
			M.flatten_node(child, root_id, id, position, out)
		end
	end

	if type(node.anchorChildren) == "table" then
		for _, child in ipairs(node.anchorChildren) do
			child.role = "popup-anchor"
			M.flatten_node(child, root_id, id, position, out)
		end
	end

	if type(node.popupChildren) == "table" then
		for _, child in ipairs(node.popupChildren) do
			child.role = "popup-content"
			M.flatten_node(child, root_id, id, position, out)
		end
	end
end

return M
