local M = {}

-- Terminal state management
local terminals = {}
local current_terminal = 1
local next_terminal_id = 1

-- Default configuration
local config = {
	width = 0.8,
	height = 0.8,
	border = "rounded",
	winblend = 0,
}

-- Setup function to override defaults
function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
end

-- Calculate window dimensions
local function get_window_config()
	local width = math.floor(vim.o.columns * config.width)
	local height = math.floor(vim.o.lines * config.height)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	return {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = config.border,
		style = "minimal",
		title = "(" .. current_terminal .. "/" .. #terminals .. ")",
		title_pos = "center",
	}
end

-- Create a new terminal
local function create_terminal()
	local buf = vim.api.nvim_create_buf(false, true)

	-- Set buffer options
	vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")
	vim.api.nvim_buf_set_option(buf, "filetype", "terminal")

	local terminal = {
		id = next_terminal_id,
		buf = buf,
		win = nil,
		job_id = nil,
	}

	terminals[next_terminal_id] = terminal
	next_terminal_id = next_terminal_id + 1

	return terminal
end

-- Open a terminal window
local function open_terminal_window(terminal)
	if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
		return -- Window already exists
	end

	local win_config = get_window_config()

	terminal.win = vim.api.nvim_open_win(terminal.buf, true, win_config)

	-- Set window options
	vim.api.nvim_win_set_option(terminal.win, "winblend", config.winblend)

	-- Start terminal if not already started
	if not terminal.job_id then
		terminal.job_id = vim.fn.termopen(vim.o.shell, {
			on_exit = function()
				terminal.job_id = nil
			end
		})
	end

	-- Enter insert mode
	vim.cmd("startinsert")

	-- Set up key mappings for the terminal buffer
	local opts = { buffer = terminal.buf, silent = true }
end

-- Close terminal window
local function close_terminal_window(terminal)
	if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
		vim.api.nvim_win_close(terminal.win, true)
		terminal.win = nil
	end
end

-- Get or create current terminal
local function get_current_terminal()
	local terminal = terminals[current_terminal]
	if not terminal then
		terminal = create_terminal()
		current_terminal = terminal.id
	end
	return terminal
end

-- Check if any terminal window is open
local function is_any_terminal_open()
	for _, terminal in pairs(terminals) do
		if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
			return true, terminal
		end
	end
	return false, nil
end

-- Main toggle function
function M.toggle()
	local is_open, open_terminal = is_any_terminal_open()

	if is_open then
		-- Close the open terminal
		close_terminal_window(open_terminal)
	else
		-- Open current terminal
		local terminal = get_current_terminal()
		open_terminal_window(terminal)
	end
end

-- Create a new terminal instance
function M.new()
	local terminal = create_terminal()
	current_terminal = terminal.id

	-- Close any open terminal first
	local is_open, open_terminal = is_any_terminal_open()
	if is_open then
		close_terminal_window(open_terminal)
	end

	open_terminal_window(terminal)
end

-- Switch to next terminal
function M.next()
	local terminal_ids = {}
	for id, _ in pairs(terminals) do
		table.insert(terminal_ids, id)
	end

	if #terminal_ids == 0 then
		M.toggle()
		return
	end

	table.sort(terminal_ids)

	local current_index = 1
	for i, id in ipairs(terminal_ids) do
		if id == current_terminal then
			current_index = i
			break
		end
	end

	local next_index = current_index + 1
	if next_index > #terminal_ids then
		next_index = 1
	end

	current_terminal = terminal_ids[next_index]

	-- Close current terminal and open next one
	local is_open, open_terminal = is_any_terminal_open()
	if is_open then
		close_terminal_window(open_terminal)
	end

	local terminal = terminals[current_terminal]
	open_terminal_window(terminal)
end

-- Switch to previous terminal
function M.prev()
	local terminal_ids = {}
	for id, _ in pairs(terminals) do
		table.insert(terminal_ids, id)
	end

	if #terminal_ids == 0 then
		M.toggle()
		return
	end

	table.sort(terminal_ids)

	local current_index = 1
	for i, id in ipairs(terminal_ids) do
		if id == current_terminal then
			current_index = i
			break
		end
	end

	local prev_index = current_index - 1
	if prev_index < 1 then
		prev_index = #terminal_ids
	end

	current_terminal = terminal_ids[prev_index]

	-- Close current terminal and open previous one
	local is_open, open_terminal = is_any_terminal_open()
	if is_open then
		close_terminal_window(open_terminal)
	end

	local terminal = terminals[current_terminal]
	open_terminal_window(terminal)
end

-- Switch to specific terminal by number
function M.go_to(terminal_id)
	if not terminals[terminal_id] then
		return
	end

	current_terminal = terminal_id

	-- Close current terminal and open the specified one
	local is_open, open_terminal = is_any_terminal_open()
	if is_open then
		close_terminal_window(open_terminal)
	end

	local terminal = terminals[current_terminal]
	open_terminal_window(terminal)
end

-- List all terminals
function M.list()
	local terminal_ids = {}
	for id, _ in pairs(terminals) do
		table.insert(terminal_ids, id)
	end

	if #terminal_ids == 0 then
		return
	end

	table.sort(terminal_ids)
end

-- Kill a specific terminal
function M.kill(terminal_id)
	local terminal = terminals[terminal_id]
	if not terminal then
		return
	end

	-- Kill the job if running
	if terminal.job_id then
		vim.fn.jobstop(terminal.job_id)
	end

	-- Delete the buffer
	if vim.api.nvim_buf_is_valid(terminal.buf) then
		vim.api.nvim_buf_delete(terminal.buf, { force = true })
	end

	-- Remove from terminals table
	local new_table = {}
	for id, term in ipairs(terminals) do
		if id ~= terminal_id then
			if id > terminal_id then
				new_table[id - 1] = term
			else
				new_table[id] = term
			end
		end
	end
	next_terminal_id = #new_table + 1
	terminals = new_table

	-- If this was the current terminal, switch to another one or create new
	if terminal_id == current_terminal then
		local remaining_ids = {}
		for id, _ in pairs(terminals) do
			table.insert(remaining_ids, id)
		end

		if #remaining_ids > 0 then
			table.sort(remaining_ids)
			current_terminal = remaining_ids[1]
		else
			current_terminal = 1
		end
		M.go_to(current_terminal)
	end

	close_terminal_window(terminal)
end

function M.kill_current()
	M.kill(current_terminal)
end

-- Kill all terminals
function M.kill_all()
	for id, _ in pairs(terminals) do
		M.kill(id)
	end
	vim.notify("All terminals killed")
end

-- Run a command in a scratch terminal
-- Run a command in a scratch terminal
function M.run_command(cmd)
	if not cmd or cmd == "" then
		vim.ui.input({ prompt = "Enter command to run: " }, function(input)
			if input and input ~= "" then
				M.run_command(input)
			end
		end)
		return
	end

	-- Create a temporary buffer for the scratch terminal
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)

	-- Create window configuration
	local win_config = get_window_config()
	win_config.title = " Running: " .. cmd .. " "

	local win = vim.api.nvim_open_win(buf, true, win_config)
	vim.api.nvim_win_set_option(win, "winblend", config.winblend)

	-- Set initial content
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "$ " .. cmd, "" })
	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	-- Run command and capture output
	local job_id = vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data, _)
			if data and #data > 0 then
				vim.schedule(function()
					if vim.api.nvim_buf_is_valid(buf) then
						vim.api.nvim_buf_set_option(buf, "modifiable", true)
						-- Filter out empty strings that jobstart sometimes adds
						local filtered_data = {}
						for _, line in ipairs(data) do
							if line ~= "" then
								table.insert(filtered_data, line)
							end
						end
						if #filtered_data > 0 then
							vim.api.nvim_buf_set_lines(buf, -1, -1, false, filtered_data)
						end
						vim.api.nvim_buf_set_option(buf, "modifiable", false)
					end
				end)
			end
		end,
		on_stderr = function(_, data, _)
			if data and #data > 0 then
				vim.schedule(function()
					if vim.api.nvim_buf_is_valid(buf) then
						vim.api.nvim_buf_set_option(buf, "modifiable", true)
						-- Filter out empty strings that jobstart sometimes adds
						local filtered_data = {}
						for _, line in ipairs(data) do
							if line ~= "" then
								table.insert(filtered_data, line)
							end
						end
						if #filtered_data > 0 then
							vim.api.nvim_buf_set_lines(buf, -1, -1, false, filtered_data)
						end
						vim.api.nvim_buf_set_option(buf, "modifiable", false)
					end
				end)
			end
		end,
		on_exit = function(_, exit_code, _)
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(buf) then
					vim.api.nvim_buf_set_option(buf, "modifiable", true)
					if exit_code ~= 0 then
						vim.api.nvim_buf_set_lines(buf, -1, -1, false,
							{ "", "[Command failed with exit code " .. exit_code .. "]" })
					end
					vim.api.nvim_buf_set_option(buf, "modifiable", false)
				end

				-- Auto-close after 2 seconds
				vim.defer_fn(function()
					if vim.api.nvim_win_is_valid(win) then
						vim.api.nvim_win_close(win, true)
					end
					if vim.api.nvim_buf_is_valid(buf) then
						vim.api.nvim_buf_delete(buf, { force = true })
					end
				end, 2000)
			end)
		end
	})

	-- Set up key mappings for manual close
	local opts = { buffer = buf, silent = true }

	-- Add keys to manually close the scratch terminal
	if not job_id or job_id <= 0 then
		print("Failed to start command: " .. cmd)
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end
end

-- Run command with custom working directory
function M.run_command_in_dir(cmd, dir)
	if not cmd or cmd == "" then
		vim.ui.input({ prompt = "Enter command to run: " }, function(input)
			if input and input ~= "" then
				if not dir or dir == "" then
					vim.ui.input({ prompt = "Enter directory: ", default = vim.fn.getcwd() }, function(directory)
						if directory and directory ~= "" then
							M.run_command_in_dir(input, directory)
						end
					end)
				else
					M.run_command_in_dir(input, dir)
				end
			end
		end)
		return
	end

	if not dir or dir == "" then
		dir = vim.fn.getcwd()
	end

	-- Change to directory and run command
	local full_cmd = "cd " .. vim.fn.shellescape(dir) .. " && " .. cmd
	M.run_command(full_cmd)
end

return M
