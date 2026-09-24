local M = {}

local HEADER_PATTERNS = { "%.h$" }
local STRIP_DECL_KEYWORDS = { "static", "inline" }

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "CExtractDefinitions" })
end

local function is_header(path)
	for _, pattern in ipairs(HEADER_PATTERNS) do
		if path:match(pattern) then return true end
	end

	return false
end

local function trim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_lines(text)
	return vim.split(text, "\n", { plain = true })
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

local function normalize_ws(text)
	return trim((text:gsub("%s+", " ")))
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

local function find_enclosing_function(node, row, col)
	local best = nil

	local function walk(current)
		if not node_contains(current, row, col) then return end

		if current:type() == "function_definition" then
			best = current
		end

		for child in iter_named_children(current) do
			walk(child)
		end
	end

	walk(node)
	return best
end

local function resolve_function_name_node(declarator)
	if not declarator then return nil end

	local kind = declarator:type()
	if kind == "identifier" or kind == "field_identifier" then
		return declarator
	end

	local name_node = get_field_child(declarator, "name")
	if name_node then return name_node end

	local inner = get_field_child(declarator, "declarator")
	if inner then
		return resolve_function_name_node(inner)
	end

	if declarator:named_child_count() == 1 then
		return resolve_function_name_node(declarator:named_child(0))
	end

	return declarator
end

local function strip_decl_only_keywords(text)
	local updated = text

	for _, keyword in ipairs(STRIP_DECL_KEYWORDS) do
		updated = updated:gsub("(%f[%a_])" .. keyword .. "(%f[^%a_])%s*", "")
	end

	return updated
end

local function build_definition_prefix(bufnr, function_node)
	local body_node = get_field_child(function_node, "body")
	local declarator = get_field_child(function_node, "declarator")
	if not body_node or not declarator then return nil, "Unsupported function declarator" end

	local name_node = resolve_function_name_node(declarator)
	if not name_node then return nil, "Unsupported function name" end

	local fsr, fsc = function_node:range()
	local bsr, bsc = body_node:range()
	local prefix = get_text_range(bufnr, fsr, fsc, bsr, bsc)

	return trim(strip_decl_only_keywords(prefix)), nil
end

local function build_declaration(bufnr, function_node)
	local body_node = get_field_child(function_node, "body")
	if not body_node then return nil end

	local fsr, fsc = function_node:range()
	local end_row, end_col = body_node:range()

	local prefix = trim(get_text_range(bufnr, fsr, fsc, end_row, end_col))
	return prefix .. ";"
end

local function build_free_function_declaration(bufnr, function_node)
	local declaration = build_declaration(bufnr, function_node)
	if not declaration then return nil end

	return trim(strip_decl_only_keywords(declaration))
end

local function build_definition_text(bufnr, function_node)
	local prefix, err = build_definition_prefix(bufnr, function_node)
	if not prefix then return nil, err end

	local body_node = get_field_child(function_node, "body")
	local body = get_node_text(body_node, bufnr)
	return prefix .. " " .. body
end

local function replace_function_with_declaration(bufnr, function_node, declaration)
	local sr, sc, er, ec = function_node:range()
	vim.api.nvim_buf_set_text(bufnr, sr, sc, er, ec, split_lines(declaration))
end

local function header_include_line(header_path)
	return string.format('#include "%s"', vim.fn.fnamemodify(header_path, ":t"))
end

local function ensure_cpp_include(cpp_path, include_line)
	local lines = {}
	if vim.fn.filereadable(cpp_path) == 1 then
		lines = vim.fn.readfile(cpp_path)
	end

	for _, line in ipairs(lines) do
		if trim(line) == include_line then return lines, false end
	end

	if #lines == 0 then
		return { include_line, "" }, true
	end

	table.insert(lines, 1, "")
	table.insert(lines, 1, include_line)
	return lines, true
end

local function append_missing_definitions(cpp_path, include_line, definition_entries)
	local lines, changed = ensure_cpp_include(cpp_path, include_line)
	local normalized_existing = normalize_ws(table.concat(lines, "\n"))
	local appended = 0

	for _, entry in ipairs(definition_entries) do
		if normalized_existing:find(entry.signature, 1, true) == nil then
			if #lines > 0 and lines[#lines] ~= "" then table.insert(lines, "") end
			vim.list_extend(lines, split_lines(entry.definition))
			normalized_existing = normalized_existing .. " " .. normalize_ws(entry.definition)
			appended = appended + 1
		end
	end

	if appended > 0 then
		changed = true
	end

	while #lines > 0 and lines[#lines] == "" do
		table.remove(lines)
	end

	if changed then
		vim.fn.writefile(lines, cpp_path)
	end

	return appended
end

local function header_to_cpp_path(path)
	return vim.fn.fnamemodify(path, ":r") .. ".c"
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

local function build_definition_entry(bufnr, function_node)
	local declaration = build_free_function_declaration(bufnr, function_node)
	local definition, err = build_definition_text(bufnr, function_node)
	if not declaration or not definition then return nil, err end

	local signature = normalize_ws(definition:match("^(.-)%s*%b{}") or definition)

	return {
		definition = definition,
		declaration = declaration,
		signature = signature,
		node = function_node,
	}, nil
end

local function collect_top_level_functions(root)
	local functions = {}

	local function walk(node)
		for child in iter_named_children(node) do
			local kind = child:type()
			if kind == "function_definition" then
				table.insert(functions, child)
			elseif kind:match("^preproc_") or kind == "linkage_specification" or kind == "declaration_list" then
				walk(child)
			end
		end
	end

	walk(root)
	return functions
end

local function extract_functions(functions, bufnr, path)
	local definition_entries = {}
	local replacements = {}

	for _, function_node in ipairs(functions) do
		local entry, err = build_definition_entry(bufnr, function_node)
		if entry then
			table.insert(definition_entries, entry)
			table.insert(replacements, { node = entry.node, declaration = entry.declaration })
		elseif err then
			notify(err, vim.log.levels.WARN)
		end
	end

	if vim.tbl_isempty(replacements) then
		notify("No supported function definitions found", vim.log.levels.WARN)
		return
	end

	for index = #replacements, 1, -1 do
		local item = replacements[index]
		replace_function_with_declaration(bufnr, item.node, item.declaration)
	end

	vim.cmd("silent write")

	local cpp_path = header_to_cpp_path(path)
	local include_line = header_include_line(path)
	local appended = append_missing_definitions(cpp_path, include_line, definition_entries)

	return #replacements, appended, cpp_path
end

function M.extract_all_functions()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)

	if path == "" or not is_header(path) then
		notify("Run this command from a C header buffer", vim.log.levels.ERROR)
		return
	end

	local tree = get_c_parser_tree(bufnr)
	if not tree then return end

	local functions = collect_top_level_functions(tree:root())
	if vim.tbl_isempty(functions) then
		notify("No function definitions found in the current header", vim.log.levels.INFO)
		return
	end

	local extracted, appended, cpp_path = extract_functions(functions, bufnr, path)
	if not extracted then return end

	notify(string.format(
		"Extracted %d definition(s) and appended %d new definition(s) to %s",
		extracted,
		appended,
		vim.fn.fnamemodify(cpp_path, ":t")
	))
end

function M.extract_current_function()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)

	if path == "" or not is_header(path) then
		notify("Run this command from a C header buffer", vim.log.levels.ERROR)
		return
	end

	local tree = get_c_parser_tree(bufnr)
	if not tree then return end
	local root = tree:root()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1
	local col = cursor[2]
	local function_node = find_enclosing_function(root, row, col)
	if not function_node then
		notify("Place the cursor inside the function definition to extract", vim.log.levels.ERROR)
		return
	end

	local name_node = resolve_function_name_node(get_field_child(function_node, "declarator"))
	local function_name = name_node and trim(get_node_text(name_node, bufnr)) or ""

	local extracted, appended, cpp_path = extract_functions({ function_node }, bufnr, path)
	if not extracted then return end

	notify(string.format(
		"Extracted %s and appended %d new definition(s) to %s",
		function_name ~= "" and function_name or "function definition",
		appended,
		vim.fn.fnamemodify(cpp_path, ":t")
	))
end

function M.setup()
	vim.api.nvim_create_user_command("CExtractDefinitions", function()
		M.extract_all_functions()
	end, {
		desc = "Extract all C function definitions from the current header into a .c file",
	})

	vim.api.nvim_create_user_command("CExtractFunctionDefinition", function()
		M.extract_current_function()
	end, {
		desc = "Extract the current C function definition into a .c file",
	})
end

return M
