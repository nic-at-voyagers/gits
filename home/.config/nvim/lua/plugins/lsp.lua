return {
      { "neovim/nvim-lspconfig",
            opts = {
                  servers = {
                        ruff = {
                              mason = false, -- Disable auto-install from mason  
                        }
                  }
            }
      },
      {
            "neovim/nvim-lspconfig",
            opts = {
                  servers = {
                        basedpyright = {
                              settings = {
                                    python = {
                                          analysis = {
                                                -- Disable Pyright's formatting  
                                                formatting = {
                                                      provider = "none"
                                                }
                                          }
                                    }
                              }
                        }
                  }
            }
      }
}
