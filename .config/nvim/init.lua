vim.opt.clipboard = "unnamedplus"

vim.g.clipboard = {
  name = 'xselOverride',
  copy = {
    ['+'] = 'xsel --clipboard --input',
    ['*'] = 'xsel --primary --input',
  },
  paste = {
    ['+'] = 'xsel --clipboard --output',
    ['*'] = 'xsel --primary --output',
  }
}
