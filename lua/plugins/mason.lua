return {
  'williamboman/mason.nvim',
  -- event = 'VeryLazy',
  cmd = {
    'Mason',
    'MasonLog',
    'MasonUpdate',
    'MasonInstall',
    'MasonUninstall',
    'MasonToolsClean',
    'MasonToolsUpdate',
    'MasonToolsInstall',
    'MasonUninstallAll',
    'MasonToolsUpdateSync',
    'MasonToolsInstallSync',
  },
  opts = {
    registries = {
      'github:mason-org/mason-registry',
      'github:Crashdummyy/mason-registry',
    },
  },
}
