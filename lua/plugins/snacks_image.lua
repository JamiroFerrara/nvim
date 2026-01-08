-- lazy.nvim
return {
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    image = {
      enabled = true,
      force = true,
      doc = {
        inline = true,
        float = true,
        max_width = 60,
        max_height = 30
      }
    },
    styles = {
      snacks_image = {
        relative = "editor",
        col = -1,
      },
    },
  }
}
