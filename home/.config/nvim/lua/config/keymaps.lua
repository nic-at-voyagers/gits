-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Typst
vim.keymap.set("n", "<Space>ms", function()
  require("typst-preview").start()
end, { desc = "Start Typst preview" })

vim.keymap.set("n", "<Space>mq", function()
  require("typst-preview").stop()
end, { desc = "Stop Typst preview" })

vim.keymap.set("n", "<Space>mn", function()
  require("typst-preview").next_page()
end, { desc = "Next page" })

vim.keymap.set("n", "<Space>mp", function()
  require("typst-preview").prev_page()
end, { desc = "Previous page" })

vim.keymap.set("n", "<Space>mr", function()
  require("typst-preview").refresh()
end, { desc = "Refresh preview" })

vim.keymap.set("n", "<Space>mgg", function()
  require("typst-preview").first_page()
end, { desc = "First page" })

vim.keymap.set("n", "<Space>mG", function()
  require("typst-preview").last_page()
end, { desc = "Last page" })

-- Open compiler
vim.api.nvim_set_keymap('n', '<F6>', "<cmd>CompilerOpen<cr>", { noremap = true, silent = true })

-- Redo last selected option
vim.api.nvim_set_keymap('n', '<S-F6>',
     "<cmd>CompilerStop<cr>" -- (Optional, to dispose all tasks before redo)
  .. "<cmd>CompilerRedo<cr>",
 { noremap = true, silent = true })

-- Toggle compiler results
vim.api.nvim_set_keymap('n', '<S-F7>', "<cmd>CompilerToggleResults<cr>", { noremap = true, silent = true })


-- Nvim-dap
vim.keymap.set("n", "<Space>dt", function()
      require("dap").toggle_breakpoint()
end, { desc = "Toggle Breakpoint" })

vim.keymap.set("n", "<Space>dc", function()
      require("dap").continue()
end, { desc = "Continue" })

vim.keymap.set("n", "<Space>di", function()
      require("dap").step_into()
end, { desc = "Step Into" })

-- Step Over
vim.keymap.set("n", "<leader>do", function()
    require("dap").step_over()
end, { desc = "Step Over", nowait = true, remap = false})

-- Step Out
vim.keymap.set("n", "<leader>du", function()
    require("dap").step_out()
end, { desc = "Step Out", nowait = true, remap = false })

-- Open REPL
vim.keymap.set("n", "<leader>dr", function()
    require("dap").repl.open()
end, { desc = "Open REPL", nowait = true, remap = false })

-- Run Last
vim.keymap.set("n", "<leader>dl", function()
    require("dap").run_last()
end, { desc = "Run Last", nowait = true, remap = false })

-- Terminate
vim.keymap.set("n", "<leader>dq", function()
    require("dap").terminate()
    require("dapui").close()
    require("nvim-dap-virtual-text").toggle()
end, { desc = "Terminate", nowait = true, remap = false })

-- List Breakpoints
vim.keymap.set("n", "<leader>db", function()
    require("dap").list_breakpoints()
end, { desc = "List Breakpoints", nowait = true, remap = false })

-- Set Exception Breakpoints
vim.keymap.set("n", "<leader>de", function()
    require("dap").set_exception_breakpoints({ "all" })
end, { desc = "Set Exception Breakpoints", nowait = true, remap = false })

-- Delete trailing whitespace
vim.keymap.set('n', '<S-F9>', ':%s/\\s\\+$//<CR>', { noremap = true })

-- Close current split
vim.keymap.set("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close current split" })

-- tab management
vim.keymap.set("n", "<Tab>", "<cmd>BufferLineCycleNext<CR>", { desc = "Go to next buffer" })
vim.keymap.set("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<CR>", { desc = "Go to previous buffer" })
