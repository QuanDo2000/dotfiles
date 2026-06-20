-- Disable markdown-preview.nvim (browser live preview) pulled in by the
-- LazyVim lang.markdown extra. It needs a node/yarn build step; the in-editor
-- render-markdown.nvim (also from the extra) covers day-to-day markdown.
return {
  { "iamcco/markdown-preview.nvim", enabled = false },
}
