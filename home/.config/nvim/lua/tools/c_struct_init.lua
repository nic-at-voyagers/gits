local M = {}

local C_KEYWORDS = {}
for _, keyword in ipairs({
	"_Alignas",
	"_Alignof",
	"_Atomic",
	"_Bool",
	"_Complex",
	"_Generic",
	"_Imaginary",
	"_Noreturn",
	"_Static_assert",
	"_Thread_local",
	"auto",
	"bool",
	"break",
	"case",
	"char",
	"const",
	"constexpr",
	"continue",
	"default",
	"do",
	"double",
	"else",
	"enum",
	"extern",
	"false",
	"float",
	"for",
	"goto",
	"if",
	"inline",
	"int",
	"long",
	"nullptr",
	"register",
	"restrict",
	"return",
	"short",
	"signed",
	"sizeof",
	"static",
	"static_assert",
	"struct",
	"switch",
	"thread_local",
	"true",
	"typedef",
	"typeof",
	"union",
	"unsigned",
	"void",
	"volatile",
	"while",
}) do
	C_KEYWORDS[keyword] = true
end

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "CStructInit" })
end

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function get_node_text(node, bufnr)
	return vim.treesitter.get_node_text(node, bufnr)
end

local function get_field_child(node, field)
	if not node then return nil end

	if node.child_by_field_name then
		return node:child_by_field_name(field)
	end

	if node.field then
		local children = node:field(field)
		if children and children[1] then return children[1] end
	end

	return nil
end

local function get_text_range(bufnr, start_row, start_col, end_row, end_col)
	return table.concat(vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {}), "\n")
end

local function node_contains(node, row, col)
	local sr, sc, er, ec = node:range()
	if row < sr or row > er then return false end
	if row == sr and col < sc then return false end
	if row == er and col >= ec then return false end
	return true
end

local function iter_named_children(node)
	local index = 0
	local count = node:named_child_count()

	return function()
		if index >= count then return nil end
		local child = node:named_child(index)
		index = index + 1
		return child
	end
end

local function find_enclosing_class(node, row, col)
	local best = nil

	local function walk(current)
		if not node_contains(current, row, col) then return end

		if current:type() == "struct_specifier" then
			best = current
		end

		for child in iter_named_children(current) do
			walk(child)
		end
	end

	walk(node)
	return best
end

local function find_first_named_child(node, wanted_type)
	for child in iter_named_children(node) do
		if child:type() == wanted_type then return child end
	end

	return nil
end

local function find_class_body(class_node)
	return get_field_child(class_node, "body") or find_first_named_child(class_node, "field_declaration_list")
end

local function get_class_name(class_node, bufnr)
	local name_node = get_field_child(class_node, "name")
	if name_node then return trim(get_node_text(name_node, bufnr)) end

	for child in iter_named_children(class_node) do
		local kind = child:type()
		if kind == "type_identifier" or kind == "identifier" then
			return trim(get_node_text(child, bufnr))
		end
	end

	return nil
end

local function find_enclosing_typedef(class_node)
	local parent = class_node:parent()
	if parent and parent:type() == "type_definition" then return parent end
	return nil
end

local function get_typedef_name(typedef_node, bufnr)
	local declarator = get_field_child(typedef_node, "declarator")
	if declarator and declarator:type() == "type_identifier" then
		return trim(get_node_text(declarator, bufnr))
	end

	return nil
end

local function normalize_ws(text)
	return trim((text:gsub("%s+", " ")))
end

local function direct_child_has_type(node, wanted_type)
	for child in iter_named_children(node) do
		if child:type() == wanted_type then return true end
	end
	return false
end

local function contains_type(node, wanted)
	if node:type() == wanted then return true end
	for child in iter_named_children(node) do
		if contains_type(child, wanted) then return true end
	end
	return false
end

local function has_function_typed_declarator(field)
	return contains_type(field, "function_declarator")
end

local function find_name_node(node)
	local field_name = get_field_child(node, "name")
	if field_name then return field_name end

	local kind = node:type()
	if kind == "field_identifier" or kind == "identifier" then return node end

	for child in iter_named_children(node) do
		local found = find_name_node(child)
		if found then return found end
	end

	return nil
end

local function is_static_field(bufnr, field)
	for child in iter_named_children(field) do
		if child:type() == "storage_class_specifier" and trim(get_node_text(child, bufnr)) == "static" then
			return true
		end
	end
	return false
end

local function strip_top_level_const(type_text)
	local updated = trim(type_text)
	updated = trim(updated:gsub("^const%f[%W]%s*", ""))
	updated = trim(updated:gsub("%s+const%s*$", ""))
	return updated
end

local function is_pointer_type(type_text)
	return type_text:find("*", 1, true) ~= nil
end

local function build_param_type(type_text)
	local raw = trim(type_text)

	if is_pointer_type(raw) then
		return trim(raw:gsub("%s+const%s*$", ""))
	end

	return normalize_ws(strip_top_level_const(raw))
end

local function sanitize_param_name(name)
	local param = name
	param = param:gsub("^m_", "")
	param = param:gsub("^_", "")
	param = param:gsub("_$", "")

	if param == "" or not param:match("^[%a_][%w_]*$") or C_KEYWORDS[param] then
		param = name .. "_value"
	end

	if param == "" or not param:match("^[%a_][%w_]*$") or C_KEYWORDS[param] then
		param = "value"
	end

	return param
end

local function unique_param_name(base, used)
	local candidate = base
	local suffix = 2

	while used[candidate] or C_KEYWORDS[candidate] do
		candidate = base .. suffix
		suffix = suffix + 1
	end

	used[candidate] = true
	return candidate
end

local function collect_decl_names(field)
	local names = {}

	for child in iter_named_children(field) do
		local kind = child:type()
		if kind == "field_identifier" then
			table.insert(names, child)
		elseif kind:match("declarator$") then
			local name_node = find_name_node(child)
			if name_node then table.insert(names, name_node) end
		end
	end

	return names
end

local function member_type_for_name(bufnr, field, name_node, first_name_node)
	if first_name_node and first_name_node ~= name_node then
		return member_type_for_name(bufnr, field, first_name_node)
	end

	local fsr, fsc = field:range()
	local nsr, nsc = name_node:range()
	return trim(get_text_range(bufnr, fsr, fsc, nsr, nsc))
end

local function collect_members(bufnr, class_node)
	local body = find_class_body(class_node)
	if not body then return nil, "Cursor is not inside a C struct definition" end

	if contains_type(body, "preproc_if")
		or contains_type(body, "preproc_ifdef")
		or contains_type(body, "preproc_ifndef")
		or contains_type(body, "preproc_else")
		or contains_type(body, "preproc_elif")
	then
		return nil, "conditional compilation inside the struct body is unsupported"
	end

	local members = {}
	local used_params = { self = true }

	for child in iter_named_children(body) do
		local kind = child:type()
		if kind == "union_specifier" then
			return nil, "union members are unsupported"
		elseif kind == "field_declaration" then
			local field_text = normalize_ws(get_node_text(child, bufnr))
			if is_static_field(bufnr, child) then
				-- Static fields are not initialized per instance.
			elseif contains_type(child, "union_specifier") then
				return nil, "union members are unsupported"
			elseif contains_type(child, "array_declarator") then
				return nil, "array members are unsupported: " .. field_text
			elseif contains_type(child, "bitfield_clause") then
				return nil, "bit-field members are unsupported: " .. field_text
			elseif has_function_typed_declarator(child) then
				return nil, "function-typed members are unsupported: " .. field_text
			elseif direct_child_has_type(child, "ERROR") or contains_type(child, "ERROR") then
				return nil, "unsupported member declaration: " .. field_text
			else
				local name_nodes = collect_decl_names(child)
				if vim.tbl_isempty(name_nodes) then
					return nil, "member has no usable name: " .. field_text
				end

				for _, name_node in ipairs(name_nodes) do
					local name = trim(get_node_text(name_node, bufnr))
					local type_text = member_type_for_name(bufnr, child, name_node, name_nodes[1])

					if type_text == "" then
						return nil, "unable to determine member type: " .. field_text
					end

					local param_type, err = build_param_type(type_text)
					if not param_type then
						return nil, err .. ": " .. field_text
					end

					table.insert(members, {
						name = name,
						param_type = param_type,
						param_name = unique_param_name(sanitize_param_name(name), used_params),
					})
				end
			end
		end
	end

	return members, nil
end

local function find_function_name_node(declarator)
	if not declarator then return nil end

	local kind = declarator:type()
	if kind == "identifier" or kind == "field_identifier" then return declarator end

	local name_node = get_field_child(declarator, "name")
	if name_node then return name_node end

	for child in iter_named_children(declarator) do
		local found = find_function_name_node(child)
		if found then return found end
	end

	return nil
end

local function has_existing_init(bufnr, root, init_name)
	local function walk(node)
		for child in iter_named_children(node) do
			local kind = child:type()
			if kind == "function_definition" or kind == "declaration" then
				local declarator = get_field_child(child, "declarator") or find_first_named_child(child, "function_declarator")
				if declarator and contains_type(declarator, "function_declarator") then
					local name_node = find_function_name_node(declarator)
					if name_node and trim(get_node_text(name_node, bufnr)) == init_name then
						return true
					end
				end
			elseif kind:match("^preproc_") or kind == "linkage_specification" or kind == "declaration_list" then
				if walk(child) then return true end
			end
		end

		return false
	end

	return walk(root)
end

local function body_indent(bufnr)
	if vim.bo[bufnr].expandtab then
		local width = vim.bo[bufnr].shiftwidth
		if width <= 0 then width = vim.bo[bufnr].tabstop end
		return string.rep(" ", width)
	end

	return "\t"
end

local function format_param(param_type, param_name)
	if param_type:sub(-1) == "*" then
		return param_type .. param_name
	end

	return param_type .. " " .. param_name
end

local function build_init_lines(self_type, init_name, members, indent, trailing_blank)
	local params = { self_type .. " *self" }

	for _, member in ipairs(members) do
		table.insert(params, format_param(member.param_type, member.param_name))
	end

	local lines = { "" }
	table.insert(lines, "static void " .. init_name .. "(" .. table.concat(params, ", ") .. ") {")

	for _, member in ipairs(members) do
		table.insert(lines, indent .. "self->" .. member.name .. " = " .. member.param_name .. ";")
	end

	table.insert(lines, "}")

	if trailing_blank then
		table.insert(lines, "")
	end

	return lines
end

local function get_c_parser_tree(bufnr)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "c")
	if not ok or not parser then
		notify("C Treesitter parser is not available", vim.log.levels.ERROR)
		return nil
	end

	local tree = parser:parse()[1]
	if not tree then
		notify("Unable to parse the current buffer", vim.log.levels.ERROR)
		return nil
	end

	return tree
end

function M.generate()
	local bufnr = vim.api.nvim_get_current_buf()
	local tree = get_c_parser_tree(bufnr)
	if not tree then return end

	local root = tree:root()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1
	local col = cursor[2]
	local class_node = find_enclosing_class(root, row, col)
	if not class_node then
		notify("Cursor is not inside a C struct definition", vim.log.levels.ERROR)
		return
	end

	local body = find_class_body(class_node)
	if not body then
		notify("Cursor is not inside a C struct definition", vim.log.levels.ERROR)
		return
	end

	local typedef_node = find_enclosing_typedef(class_node)
	local struct_name = get_class_name(class_node, bufnr)
	local self_type
	local init_name

	if struct_name and struct_name ~= "" then
		self_type = "struct " .. struct_name
		init_name = struct_name .. "_init"
	else
		local typedef_name = typedef_node and get_typedef_name(typedef_node, bufnr) or nil
		if not typedef_name or typedef_name == "" then
			notify("Unable to resolve the struct name", vim.log.levels.ERROR)
			return
		end

		self_type = typedef_name
		init_name = typedef_name .. "_init"
	end

	local members, err = collect_members(bufnr, class_node)
	if not members then
		notify(err, vim.log.levels.WARN)
		return
	end

	if vim.tbl_isempty(members) then
		notify("No eligible members found", vim.log.levels.INFO)
		return
	end

	if has_existing_init(bufnr, root, init_name) then
		notify(init_name .. " already exists", vim.log.levels.INFO)
		return
	end

	local anchor = typedef_node or class_node
	local _, _, end_row = anchor:range()
	local insert_row = end_row + 1
	local next_line = vim.api.nvim_buf_get_lines(bufnr, insert_row, insert_row + 1, false)[1]
	local trailing_blank = next_line ~= nil and trim(next_line) ~= ""
	local lines = build_init_lines(self_type, init_name, members, body_indent(bufnr), trailing_blank)

	vim.api.nvim_buf_set_lines(bufnr, insert_row, insert_row, false, lines)
	notify("Generated " .. init_name)
end

function M.setup()
	vim.api.nvim_create_user_command("CStructInit", function()
		M.generate()
	end, {
		desc = "Generate a <Struct>_init function that assigns every member of the current C struct",
	})
end

return M
