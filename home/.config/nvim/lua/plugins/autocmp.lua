return {
  "saghen/blink.cmp",
  -- Make blink.cmp toogleable
  opts = function(_, opts)
    vim.g.completion = false

    Snacks.toggle({
      name = "Completion",
      get = function()
        if vim.b.completion == nil then
          return vim.g.completion
        end
        return vim.b.completion
      end,
      set = function(state)
        vim.b.completion = state
      end,
    }):map("<leader>uk")

    opts.enabled = function()
      local state = vim.b.completion
      if state == nil then
        state = vim.g.completion
      end
      return state == true
    end
    return opts
  end,
}
