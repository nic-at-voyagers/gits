-- Ghost in the Shell: thin square frames (┌─┐ like the prompt) instead of rounded ones.
-- snacks, blink.cmp and every other float that doesn't pin its own border follow this.
vim.o.winborder = "single"

vim.opt.fillchars:append({
  eob = " ",
  vert = "│",
  horiz = "─",
  horizup = "┴",
  horizdown = "┬",
  vertleft = "┤",
  vertright = "├",
  verthoriz = "┼",
  fold = " ",
  foldsep = "│",
  foldopen = "▾",
  foldclose = "▸",
})
