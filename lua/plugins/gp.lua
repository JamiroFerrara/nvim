return {
  'robitx/gp.nvim',
  -- event = 'VeryLazy',
  cmd = {
    'GpChatNew',
    'GpChatToggle'
  },
  config = function()
    local handle = io.popen '/home/jferrara/.scripts/cgptapikey.sh'
    local api_key = handle:read('*a'):gsub('%s+', '')
    handle:close()

    require('gp').setup {
      chat_shortcut_respond = { modes = { 'n', 'v', 'x' }, shortcut = '<cr>' },
      default_command_agent = 'ChatGPT4o',
      default_chat_agent = 'ChatGPT4o',
      providers = {
        openai = {
          endpoint = 'https://api.openai.com/v1/chat/completions',
          secret = api_key,
        },
      },
      agents = {
        {
          name = 'ExampleDisabledAgent',
          disable = true,
        },
        {
          name = 'ChatGPT4o',
          chat = true,
          command = true,
          -- string with model name or table with model name and parameters
          model = { model = 'gpt-4o', temperature = 1.1, top_p = 1 },
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

		-- your own functions can go here, see README for more examples like
		-- :GpExplain, :GpUnitTests.., :GpTranslator etc.

		-- -- example of making :%GpChatNew a dedicated command which
		-- -- opens new chat with the entire current buffer as a context
		-- BufferChatNew = function(gp, _)
		-- 	-- call GpChatNew command in range mode on whole buffer
		-- 	vim.api.nvim_command("%" .. gp.config.cmd_prefix .. "ChatNew")
		-- end,

		-- -- example of adding command which opens new chat dedicated for translation
		-- Translator = function(gp, params)
		-- 	local chat_system_prompt = "You are a Translator, please translate between English and Chinese."
		-- 	gp.cmd.ChatNew(params, chat_system_prompt)
		--
		-- 	-- -- you can also create a chat with a specific fixed agent like this:
		-- 	-- local agent = gp.get_chat_agent("ChatGPT4o")
		-- 	-- gp.cmd.ChatNew(params, chat_system_prompt, agent)
		-- end,

		-- -- example of adding command which writes unit tests for the selected code
		-- UnitTests = function(gp, params)
		-- 	local template = "I have the following code from {{filename}}:\n\n"
		-- 		.. "```{{filetype}}\n{{selection}}\n```\n\n"
		-- 		.. "Please respond by writing table driven unit tests for the code above."
		-- 	local agent = gp.get_command_agent()
		-- 	gp.Prompt(params, gp.Target.enew, agent, template)
		-- end,

		-- -- example of adding command which explains the selected code
		-- Explain = function(gp, params)
		-- 	local template = "I have the following code from {{filename}}:\n\n"
		-- 		.. "```{{filetype}}\n{{selection}}\n```\n\n"
		-- 		.. "Please respond by explaining the code above."
		-- 	local agent = gp.get_chat_agent()
		-- 	gp.Prompt(params, gp.Target.popup, agent, template)
		-- end,
	},

    }
  end,
}
