return {
  'robitx/gp.nvim',
  config = function()
    require('gp').setup {
      default_command_agent = 'ChatGPT4o',
      default_chat_agent = 'ChatGPT4o',
      providers = {
        openai = {
          endpoint = 'https://api.openai.com/v1/chat/completions',
          secret = '',
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
          command = false,
          -- string with model name or table with model name and parameters
          model = { model = 'gpt-4o', temperature = 1.1, top_p = 1 },
          -- system prompt (use this to specify the persona/role of the AI)
          -- system_prompt = require('gp.defaults').chat_system_prompt,
          system_prompt = "You are a coding assistant. Help with writing, understanding, and refactoring code. Be concise, clear, and focus only on what's necessary. Provide relevant explanations or examples when needed. Optimize for readability and efficiency. Adapt based on user interactions to improve guidance continuously. Answer with the minimum amount of words possible.",
        },
      },
    }
  end,
}
