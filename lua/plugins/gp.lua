return {
  'robitx/gp.nvim',
  -- event = 'VeryLazy',
  lazy = true,
  cmd = {
    'GpChatNew',
    'GpChatToggle',
    'GpImplement',
    'GpConvert',
    'GpCustomCmd',
    'GpOrganize',
    'GpOptimize',
    'GpComplete',
    'GpTranslate',
    'GpSummarize',
    'GpFixBugs',
    'GpExplain',
    'GpReadability',
  },
  config = function()
    local handle = io.popen '/home/jferrara/.scripts/cgptapikey.sh'
    local open_ai_key = handle:read('*a'):gsub('%s+', '')
    handle:close()

    require('gp').setup {
      chat_shortcut_respond = { modes = { 'n', 'i', 'v', 'x' }, shortcut = '<M-e>' },
      default_command_agent = 'ChatGPT4o',
      default_chat_agent = 'ChatGPT4o',
      providers = {
        openai = {
          endpoint = 'https://api.openai.com/v1/chat/completions',
          secret = open_ai_key,
        },
	cerebras = {
	  endpoint = "https://api.cerebras.ai/v1/chat/completions",
	  secret = "csk-p99wtxk93em9n8d5t5hrcncyv9h6nhj4h885wnd9ykk3khcc",
	},
      },
      agents = {
        {
          name = 'ExampleDisabledAgent',
          disable = true,
        },
        {
          name = 'ChatGPT4o',
          disable = true,
          chat = true,
          command = true,
          -- string with model name or table with model name and parameters
          model = { model = 'gpt-4o', temperature = 1.1, top_p = 1 },
          -- system prompt (use this to specify the persona/role of the AI)
          -- system_prompt = require('gp.defaults').chat_system_prompt,
          system_prompt = "You are a coding assistant. Help with writing, understanding, and refactoring code. Be concise, clear, and focus only on what's necessary. Provide relevant explanations or examples when needed. Optimize for readability and efficiency. Adapt based on user interactions to improve guidance continuously. Answer with the minimum amount of words possible.",
        },
        {
          name = 'Cerebras',
          chat = true,
	  provider = "cerebras",
          command = true,
          -- string with model name or table with model name and parameters
          model = { model = 'gpt-oss-120b', temperature = 1.1, top_p = 1 },
          -- system prompt (use this to specify the persona/role of the AI)
          -- system_prompt = require('gp.defaults').chat_system_prompt,
          system_prompt = "You are a coding assistant. Help with writing, understanding, and refactoring code. Be concise, clear, and focus only on what's necessary. Provide relevant explanations or examples when needed. Optimize for readability and efficiency. Adapt based on user interactions to improve guidance continuously. Answer with the minimum amount of words possible.",
        },
      },
      	hooks = {
		-- GpInspectPlugin provides a detailed inspection of the plugin state
		InspectPlugin = function(plugin, params)
			local bufnr = vim.api.nvim_create_buf(false, true)
			local copy = vim.deepcopy(plugin)
			local key = copy.config.openai_api_key or ""
			copy.config.openai_api_key = key:sub(1, 3) .. string.rep("*", #key - 6) .. key:sub(-3)
			local plugin_info = string.format("Plugin structure:\n%s", vim.inspect(copy))
			local params_info = string.format("Command params:\n%s", vim.inspect(params))
			local lines = vim.split(plugin_info .. "\n" .. params_info, "\n")
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
			vim.api.nvim_win_set_buf(0, bufnr)
		end,

		-- GpInspectLog for checking the log file
		InspectLog = function(plugin, params)
			local log_file = plugin.config.log_file
			local buffer = plugin.helpers.get_buffer(log_file)
			if not buffer then
				vim.cmd("e " .. log_file)
			else
				vim.cmd("buffer " .. buffer)
			end
		end,

		-- GpImplement rewrites the provided selection/range based on comments in it
		Implement = function(gp, params)
			local template = "Having following from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please rewrite this according to the contained instructions."
				.. "\n\nRespond exclusively with the snippet that should replace the selection above."

			local agent = gp.get_command_agent()
			gp.logger.info("Implementing selection with agent: " .. agent.name)

			gp.Prompt(
				params,
				gp.Target.rewrite,
				agent,
				template,
				nil, -- command will run directly without any prompting for user input
				nil -- no predefined instructions (e.g. speech-to-text from Whisper)
			)
		end,

		-- GpCustomCmd asks for an instruction and runs it on the selection
		CustomCmd = function(gp, params)
			local template = "Having following from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "{{command}}"
				.. "\n\nRespond exclusively with the result."

			local agent = gp.get_command_agent()
			gp.logger.info("Implementing selection with agent: " .. agent.name)

			gp.Prompt(
				params,
				gp.Target.rewrite,
				agent,
				template,
				"What do you want to do?", -- command will run directly without any prompting for user input
				nil -- no predefined instructions (e.g. speech-to-text from Whisper)
			)
		end,

		-- GpOrganize restructures selected code for clarity and consistency
		Organize = function(gp, params)
			local agent = gp.get_command_agent()
			local template = "Having following from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please reorganize this code to be well-structured and clean."
				.. "\n\nRespond exclusively with the reorganized code."
			gp.Prompt(params, gp.Target.rewrite, agent, template, nil, nil)
		end,

		-- GpOptimize improves selected code for performance and readability
		Optimize = function(gp, params)
			local agent = gp.get_command_agent()
			local template = "Having following from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please optimize this code for better performance and readability."
				.. "\n\nRespond exclusively with the optimized code."
			gp.Prompt(params, gp.Target.rewrite, agent, template, nil, nil)
		end,

		-- GpComplete fills in code based on comments/TODOs in the selection
		Complete = function(gp, params)
			local agent = gp.get_command_agent()
			local template = "Having following from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please complete this code based on contained comments, TODOs, and context."
				.. "\n\nRespond exclusively with the completed code."
			gp.Prompt(params, gp.Target.rewrite, agent, template, nil, nil)
		end,

		-- GpTranslate asks for the target language, then rewrites the selection
		Translate = function(gp, params)
			local target = vim.fn.input('Translate to: ')
			if target == '' then return end
			local agent = gp.get_command_agent()
			local template = "Having following from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please translate this to " .. target .. "."
				.. "\n\nRespond exclusively with the translated output."
			gp.Prompt(params, gp.Target.rewrite, agent, template, nil, nil)
		end,

		-- GpSummarize outputs a summary in a new buffer
		Summarize = function(gp, params)
			local agent = gp.get_command_agent()
			local template = "Having following from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please provide a concise summary of the above."
			gp.Prompt(params, gp.Target.enew, agent, template, nil, nil)
		end,

		-- GpFixBugs finds and fixes issues in the selected code
		FixBugs = function(gp, params)
			local agent = gp.get_command_agent()
			local template = "Having following from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please fix any bugs or issues in this code."
				.. "\n\nRespond exclusively with the fixed code."
			gp.Prompt(params, gp.Target.rewrite, agent, template, nil, nil)
		end,

		-- GpExplain shows a popup explaining the selected code
		Explain = function(gp, params)
			local agent = gp.get_command_agent()
			local template = "Having following from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please explain what this code does, including any important details."
			gp.Prompt(params, gp.Target.popup, agent, template, nil, nil)
		end,

		-- GpReadability shows a popup with readability analysis and suggestions
		Readability = function(gp, params)
			local agent = gp.get_command_agent()
			local template = "Having following from {{filename}}:\n\n"
				.. "```{{filetype}}\n{{selection}}\n```\n\n"
				.. "Please analyze the readability of this code and suggest improvements."
			gp.Prompt(params, gp.Target.popup, agent, template, nil, nil)
		end,
	},

    }
  end,
}
