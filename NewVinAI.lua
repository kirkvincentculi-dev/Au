--[[
  VinAI: one-file AI chat for Roblox (ChatGPT-style UI, powered by Claude)
  Made by Vincent (Evilmorty_143)

  SETUP (about 1 minute)
   1. Roblox Studio > ServerScriptService > insert a *Script* and paste this whole file.
   2. Explorer > HttpService > tick "HttpEnabled"
      (or Game Settings > Security > Allow HTTP Requests).
   3. Select the Script > Properties > Attributes > add an attribute named  ApiKey
      (type string) and paste your Anthropic API key (console.anthropic.com).
   4. Press Play. Click the VinAI logo button (top-right) to open or close the chat.

  HOW IT WORKS
   - The same file runs on the server (talks to Claude, keeps your key safe) and,
     as an automatic copy of itself, on each player's client (draws the UI).
   - Your API key is removed from the client copy, so players never receive it.
   - If the window never appears, paste this same file into a LocalScript in
     StarterPlayerScripts as well. It is safe to have both.
   - Logo blank? rbxassetid://72694888911234 may be a Decal ID. Use the Image ID instead.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

------------------------------------------------------------------ CONFIG
local LOGO = "rbxassetid://72694888911234"
local SATURN_KEY = "5201314" -- unlocks the Heavyweight (Saturn) mode
local MODELS = { saturn = "claude-opus-5-5", venus = "claude-sonnet-5-5", mercury = "claude-haiku-5-5" }
local TOKENS = { saturn = 4096, venus = 2048, mercury = 1024 }
local LANGS = { en = "English", es = "Spanish", ceb = "Cebuano", tl = "Tagalog", pt = "Portuguese", ru = "Russian" }
local MODE_RULES = {
	mercury = "MODE Mercury (lightweight): be fast and concise. Short answers, minimal fluff.",
	venus = "MODE Venus (medium weight): balanced depth. Explain briefly, then show clean code.",
	saturn = "MODE Saturn (heavyweight): think very hard. Plan first, handle edge cases and performance, write production-quality commented code, double-check it, then note pitfalls.",
}

local function systemPrompt(mode, lang)
	return "You are VinAI, an AI assistant that is excellent at Lua and Roblox Luau and can help with any topic, combining ChatGPT-style helpfulness with Gemini-style breadth. "
		.. "You were made by Vincent, also known as Evilmorty_143. If someone sincerely asks which model powers you, say you run on Claude by Anthropic. "
		.. "You understand and write English, Spanish, Cebuano, Tagalog (including Taglish), Portuguese and Russian. "
		.. "Reply in " .. LANGS[lang] .. " unless the user asks for another language. "
		.. "Be hardworking: reason carefully, never give lazy or half-finished code, handle edge cases, and put all code in fenced blocks (```lua for Lua). "
		.. "For Roblox code prefer modern Luau (task.wait instead of wait, GetService, no deprecated APIs) and say which script type to use and where to put it. "
		.. "For general questions be accurate, clear and thorough, and use web search when you need current information. "
		.. "Use light Markdown only (bold, bullet lists, code fences) and no tables. "
		.. MODE_RULES[mode]
end

------------------------------------------------------------------ SERVER
local function server()
	local unlocked, lastCall, attempts = {}, {}, {}
	pcall(function() HttpService.HttpEnabled = true end)

	local remote = Instance.new("RemoteFunction")
	remote.Name = "VinAI_Remote"
	remote.Parent = ReplicatedStorage

	local function ask(player, mode, lang, history)
		if not MODELS[mode] then mode = "venus" end
		if not LANGS[lang] then lang = "en" end
		if mode == "saturn" and not unlocked[player.UserId] then
			return { ok = false, error = "Saturn is locked. Enter the access key first." }
		end
		local key = script:GetAttribute("ApiKey")
		if type(key) ~= "string" or #key < 10 then
			return { ok = false, error = "No API key yet. Select the VinAI script, add an Attribute named ApiKey (string) and paste your Anthropic key." }
		end
		if type(history) ~= "table" then return { ok = false, error = "Bad request." } end

		local msgs = {}
		for i = math.max(1, #history - 13), #history do
			local m = history[i]
			if type(m) == "table" and (m.role == "user" or m.role == "assistant") and type(m.content) == "string" then
				table.insert(msgs, { role = m.role, content = m.content:sub(1, 6000) })
			end
		end
		while msgs[1] and msgs[1].role ~= "user" do table.remove(msgs, 1) end
		if #msgs == 0 or msgs[#msgs].role ~= "user" then return { ok = false, error = "Bad request." } end

		local now = os.clock()
		if lastCall[player.UserId] and now - lastCall[player.UserId] < 2 then
			return { ok = false, error = "Easy there. Wait a moment, then send again." }
		end
		lastCall[player.UserId] = now

		local sys = systemPrompt(mode, lang)
		local function req(withTools)
			local body = { model = MODELS[mode], max_tokens = TOKENS[mode], system = sys, messages = msgs }
			if withTools then
				body.tools = { { type = "web_search_20250305", name = "web_search", max_uses = 3 } }
			end
			return HttpService:RequestAsync({
				Url = "https://api.anthropic.com/v1/messages",
				Method = "POST",
				Headers = { ["x-api-key"] = key, ["anthropic-version"] = "2023-06-01", ["content-type"] = "application/json" },
				Body = HttpService:JSONEncode(body),
			})
		end

		local ok, res = pcall(req, true) -- with live web search
		if ok and not res.Success and res.StatusCode == 400 then
			ok, res = pcall(req, false) -- retry without web search if it is not enabled on the key
		end
		if not ok then
			local e = tostring(res)
			if e:lower():find("http requests are not enabled", 1, true) then
				e = "HTTP requests are off. Tick HttpEnabled on the HttpService object (or Game Settings > Security > Allow HTTP Requests)."
			end
			return { ok = false, error = e }
		end

		local good, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if not res.Success then
			local m = good and type(data) == "table" and type(data.error) == "table" and data.error.message
			return { ok = false, error = m or ("The AI service returned HTTP " .. tostring(res.StatusCode)) }
		end
		local parts = {}
		if good and type(data.content) == "table" then
			for _, b in ipairs(data.content) do
				if b.type == "text" and type(b.text) == "string" then table.insert(parts, b.text) end
			end
		end
		local text = table.concat(parts)
		if text == "" then return { ok = false, error = "The AI sent an empty answer. Try again." } end
		return { ok = true, text = text }
	end

	remote.OnServerInvoke = function(player, action, a, b, c)
		if action == "chat" then return ask(player, a, b, c) end
		if action == "unlock" then
			local id = player.UserId
			attempts[id] = (attempts[id] or 0) + 1
			if attempts[id] > 8 then return false end
			if type(a) == "string" and a:match("^%s*(.-)%s*$") == SATURN_KEY then
				unlocked[id] = true
				return true
			end
			return false
		end
	end

	-- Send a copy of this very file to each player's client (key stripped out).
	local function inject(player)
		local pg = player:WaitForChild("PlayerGui")
		if pg:FindFirstChild("VinAIClient") then return end
		local copy = script:Clone()
		copy.Name = "VinAIClient"
		copy:SetAttribute("ApiKey", nil)
		copy.RunContext = Enum.RunContext.Client
		copy.Parent = pg
	end
	Players.PlayerAdded:Connect(inject)
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(inject, p) end
	Players.PlayerRemoving:Connect(function(p)
		unlocked[p.UserId] = nil
		lastCall[p.UserId] = nil
		attempts[p.UserId] = nil
	end)
end

------------------------------------------------------------------ CLIENT (UI)
-- { heading, subtitle, placeholder, new chat, thinking, chips }
local T = {
	en = { "Hello, I’m VinAI", "Your Lua coding partner. Ask me anything.", "Message VinAI…", "New chat", "Thinking", { "Write a Lua fibonacci function", "Make a Roblox kill brick", "Why is the sky blue?" } },
	es = { "Hola, soy VinAI", "Tu compañero para programar en Lua. Pregúntame lo que quieras.", "Escribe a VinAI…", "Nuevo chat", "Pensando", { "Escribe una función de Fibonacci en Lua", "Crea un ladrillo que mata en Roblox", "¿Por qué el cielo es azul?" } },
	ceb = { "Hello, ako si VinAI", "Imong kauban sa pag-code og Lua. Pangutana bisan unsa.", "Mensahe kay VinAI…", "Bag-ong chat", "Naghunahuna", { "Pagsulat og Lua fibonacci function", "Himoa ang Roblox kill brick", "Ngano nga asul ang langit?" } },
	tl = { "Kumusta, ako si VinAI", "Kasama mo sa pag-code ng Lua. Magtanong ng kahit ano.", "Mag-message kay VinAI…", "Bagong chat", "Nag-iisip", { "Gumawa ng Lua fibonacci function", "Gumawa ng Roblox kill brick", "Bakit asul ang langit?" } },
	pt = { "Olá, eu sou o VinAI", "Seu parceiro de código em Lua. Pergunte o que quiser.", "Envie uma mensagem ao VinAI…", "Novo chat", "Pensando", { "Escreva uma função de Fibonacci em Lua", "Crie um kill brick no Roblox", "Por que o céu é azul?" } },
	ru = { "Привет, я VinAI", "Твой помощник по коду на Lua. Спрашивай что угодно.", "Напишите VinAI…", "Новый чат", "Думаю", { "Напиши функцию Фибоначчи на Lua", "Сделай kill brick в Roblox", "Почему небо голубое?" } },
}
local LANG_LIST = { { "en", "English" }, { "es", "Español" }, { "ceb", "Cebuano" }, { "tl", "Tagalog" }, { "pt", "Português" }, { "ru", "Русский" } }
local MODE_LIST = { { "saturn", "Saturn · Heavyweight" }, { "venus", "Venus · Medium weight" }, { "mercury", "Mercury · Lightweight" } }

local function client()
	local player = Players.LocalPlayer
	local pg = player:WaitForChild("PlayerGui")
	if pg:FindFirstChild("VinAI") then return end
	local remote = ReplicatedStorage:WaitForChild("VinAI_Remote", 30)
	if not remote then
		warn("VinAI: server part not found. Put this file in a Script inside ServerScriptService.")
		return
	end

	local C = {
		bg = Color3.fromRGB(33, 33, 33), side = Color3.fromRGB(23, 23, 23), bub = Color3.fromRGB(48, 48, 48),
		tx = Color3.fromRGB(236, 236, 236), mu = Color3.fromRGB(155, 155, 155), code = Color3.fromRGB(14, 14, 15),
		red = Color3.fromRGB(230, 90, 90),
	}
	local AY, AXY, LO, LEFT = Enum.AutomaticSize.Y, Enum.AutomaticSize.XY, Enum.SortOrder.LayoutOrder, Enum.TextXAlignment.Left
	local mode, lang, unlocked, busy = "venus", "en", false, false
	local chats, current = {}, nil

	local function N(class, props, parent)
		local o = Instance.new(class)
		for k, v in pairs(props) do o[k] = v end
		if parent then o.Parent = parent end
		return o
	end
	local function round(o, r) N("UICorner", { CornerRadius = UDim.new(0, r) }, o) return o end
	local function pad(o, p) N("UIPadding", { PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p), PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p) }, o) return o end
	local function label(parent, props)
		local p = { BackgroundTransparency = 1, TextColor3 = C.tx, Font = Enum.Font.Gotham, TextSize = 15 }
		for k, v in pairs(props) do p[k] = v end
		return N("TextLabel", p, parent)
	end
	local function button(parent, props)
		local p = { BackgroundColor3 = C.bub, TextColor3 = C.tx, Font = Enum.Font.Gotham, TextSize = 14, AutoButtonColor = true }
		for k, v in pairs(props) do p[k] = v end
		return N("TextButton", p, parent)
	end

	-- window
	local gui = N("ScreenGui", { Name = "VinAI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 50 }, pg)
	local win = N("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.92, 0.88), BackgroundColor3 = C.bg, ClipsDescendants = true }, gui)
	round(win, 14)
	N("UISizeConstraint", { MaxSize = Vector2.new(1100, 720) }, win)
	local toggle = N("ImageButton", { Image = LOGO, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = C.side, ZIndex = 100 }, gui)
	round(toggle, 21)
	toggle.Activated:Connect(function() win.Visible = not win.Visible end)

	-- sidebar
	local side = N("Frame", { Size = UDim2.new(0, 210, 1, 0), BackgroundColor3 = C.side, BorderSizePixel = 0 }, win)
	round(N("ImageLabel", { Image = LOGO, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(32, 32), BackgroundTransparency = 1 }, side), 16)
	label(side, { Text = "VinAI", Font = Enum.Font.GothamBold, TextSize = 18, Position = UDim2.fromOffset(52, 12), Size = UDim2.fromOffset(120, 32), TextXAlignment = LEFT })
	local newBtn = button(side, { Position = UDim2.fromOffset(12, 56), Size = UDim2.new(1, -24, 0, 36), Font = Enum.Font.GothamMedium })
	round(newBtn, 10)
	local hist = N("ScrollingFrame", { Position = UDim2.fromOffset(0, 102), Size = UDim2.new(1, 0, 1, -150), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, AutomaticCanvasSize = AY, CanvasSize = UDim2.new() }, side)
	N("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = LO, HorizontalAlignment = Enum.HorizontalAlignment.Center }, hist)
	label(side, { Text = "Made by Vincent (Evilmorty_143)\nPowered by Claude", TextSize = 12, TextColor3 = C.mu, Position = UDim2.new(0, 12, 1, -44), Size = UDim2.new(1, -24, 0, 40), TextXAlignment = LEFT, TextWrapped = true })

	-- main area
	local main = N("Frame", { Position = UDim2.fromOffset(210, 0), Size = UDim2.new(1, -210, 1, 0), BackgroundTransparency = 1 }, win)
	local head = N("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, ZIndex = 10 }, main)
	local menu = button(head, { Text = "☰", Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1, TextSize = 20 })

	local function setSide(on)
		side.Visible = on
		main.Position = UDim2.fromOffset(on and 210 or 0, 0)
		main.Size = UDim2.new(1, on and -210 or 0, 1, 0)
	end
	menu.Activated:Connect(function() setSide(not side.Visible) end)
	local cam = workspace.CurrentCamera
	setSide(not (cam and cam.ViewportSize.X < 700))

	local function dropdown(pos, w, getItems, onPick)
		local btn = button(head, { AnchorPoint = Vector2.new(1, 0), Position = pos, Size = UDim2.fromOffset(w, 28), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd })
		round(btn, 14)
		local list = N("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(pos.X.Scale, pos.X.Offset, 0, 42), Size = UDim2.fromOffset(w + 30, 0), AutomaticSize = AY, BackgroundColor3 = C.bub, Visible = false }, head)
		round(list, 10)
		N("UIListLayout", { SortOrder = LO }, list)
		btn.Activated:Connect(function()
			for _, ch in ipairs(list:GetChildren()) do
				if ch:IsA("TextButton") then ch:Destroy() end
			end
			for i, it in ipairs(getItems()) do
				local b = button(list, { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, Text = it[2], TextSize = 13, LayoutOrder = i })
				b.Activated:Connect(function()
					list.Visible = false
					onPick(it[1])
				end)
			end
			list.Visible = not list.Visible
		end)
		return btn
	end

	-- hero (empty-chat greeting)
	local hero = N("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 80), Size = UDim2.new(1, -40, 0, 0), AutomaticSize = AY, BackgroundTransparency = 1 }, main)
	N("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = LO, HorizontalAlignment = Enum.HorizontalAlignment.Center }, hero)
	N("UISizeConstraint", { MaxSize = Vector2.new(520, math.huge) }, hero)
	local heroTitle = label(hero, { Size = UDim2.new(1, 0, 0, 46), TextSize = 32, Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), LayoutOrder = 1 })
	N("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(66, 133, 244), Color3.fromRGB(217, 101, 112)) }, heroTitle)
	local heroSub = label(hero, { Size = UDim2.new(1, 0, 0, 40), TextColor3 = C.mu, TextWrapped = true, LayoutOrder = 2 })
	local chipBtns = {}
	for i = 1, 3 do
		chipBtns[i] = round(button(hero, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2 + i }), 12)
	end

	-- composer
	local comp = N("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -28, 0, 48), BackgroundColor3 = C.bub }, main)
	round(comp, 24)
	N("UISizeConstraint", { MaxSize = Vector2.new(760, 48) }, comp)
	local box = N("TextBox", { Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -66, 1, 0), BackgroundTransparency = 1, TextColor3 = C.tx, PlaceholderColor3 = C.mu, Font = Enum.Font.Gotham, TextSize = 15, TextXAlignment = LEFT, ClearTextOnFocus = false, Text = "" }, comp)
	local sendBtn = button(comp, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = C.tx, TextColor3 = C.bg, Text = "↑", Font = Enum.Font.GothamBold, TextSize = 18 })
	round(sendBtn, 17)

	-- Saturn key dialog
	local modal = N("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 190), BackgroundColor3 = C.side, Visible = false, ZIndex = 50 }, win)
	round(modal, 14)
	label(modal, { Text = "Saturn · Heavyweight", Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 24), TextXAlignment = LEFT })
	label(modal, { Text = "Enter the access key to unlock this mode.", TextSize = 13, TextColor3 = C.mu, Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 20), TextXAlignment = LEFT })
	local keyBox = round(N("TextBox", { Position = UDim2.fromOffset(16, 70), Size = UDim2.new(1, -32, 0, 36), BackgroundColor3 = C.bub, TextColor3 = C.tx, Font = Enum.Font.Gotham, TextSize = 15, PlaceholderText = "Access key", PlaceholderColor3 = C.mu, Text = "", ClearTextOnFocus = true }, modal), 8)
	local keyMsg = label(modal, { Text = "", TextSize = 13, TextColor3 = C.red, Position = UDim2.fromOffset(16, 110), Size = UDim2.new(1, -32, 0, 18), TextXAlignment = LEFT })
	local cancelBtn = round(button(modal, { Text = "Cancel", Position = UDim2.fromOffset(16, 138), Size = UDim2.new(0.5, -22, 0, 36) }), 10)
	local unlockBtn = round(button(modal, { Text = "Unlock", Position = UDim2.new(0.5, 6, 0, 138), Size = UDim2.new(0.5, -22, 0, 36), BackgroundColor3 = C.tx, TextColor3 = C.bg }), 10)

	-- mode + language dropdowns
	local function modeLabel(k)
		for _, m in ipairs(MODE_LIST) do
			if m[1] == k then return (k == "saturn" and not unlocked) and (m[2] .. " 🔒") or m[2] end
		end
	end
	local modeBtn, langBtn
	local function refreshMode() modeBtn.Text = modeLabel(mode) end
	modeBtn = dropdown(UDim2.new(1, -118, 0, 10), 170, function()
		local items = {}
		for _, m in ipairs(MODE_LIST) do table.insert(items, { m[1], modeLabel(m[1]) }) end
		return items
	end, function(k)
		if k == "saturn" and not unlocked then
			keyBox.Text, keyMsg.Text = "", ""
			modal.Visible = true
			return
		end
		mode = k
		refreshMode()
	end)
	langBtn = dropdown(UDim2.new(1, -10, 0, 10), 100, function() return LANG_LIST end, function(k)
		lang = k
		for _, l in ipairs(LANG_LIST) do if l[1] == k then langBtn.Text = l[2] end end
		local t = T[lang]
		heroTitle.Text, heroSub.Text, box.PlaceholderText = t[1], t[2], t[3]
		newBtn.Text = "+  " .. t[4]
		for i, b in ipairs(chipBtns) do b.Text = t[6][i] end
	end)
	cancelBtn.Activated:Connect(function() modal.Visible = false end)
	unlockBtn.Activated:Connect(function()
		task.spawn(function()
			local ok, res = pcall(function() return remote:InvokeServer("unlock", keyBox.Text) end)
			if ok and res == true then
				unlocked, mode = true, "saturn"
				modal.Visible = false
				refreshMode()
			else
				keyMsg.Text = "Wrong key. Try again."
			end
		end)
	end)

	-- chats
	local function refreshSide()
		for _, ch in ipairs(hist:GetChildren()) do
			if ch:IsA("TextButton") then ch:Destroy() end
		end
		for i = #chats, 1, -1 do
			local chat = chats[i]
			local b = button(hist, { Size = UDim2.new(1, -16, 0, 34), BackgroundTransparency = (chat == current) and 0 or 1, Text = chat.title, TextXAlignment = LEFT, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = #chats - i })
			round(b, 8)
			N("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, b)
			b.Activated:Connect(function() current = chat; for _, c in ipairs(chats) do c.scroll.Visible = (c == chat) end hero.Visible = (#chat.history == 0); refreshSide() end)
		end
	end
	local function openChat(chat)
		current = chat
		for _, c in ipairs(chats) do c.scroll.Visible = (c == chat) end
		hero.Visible = (#chat.history == 0)
		refreshSide()
	end
	local function newChat()
		local sc = N("ScrollingFrame", { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 1, -128), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, AutomaticCanvasSize = AY, CanvasSize = UDim2.new(), Visible = false }, main)
		N("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = LO, HorizontalAlignment = Enum.HorizontalAlignment.Center }, sc)
		N("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, sc)
		local chat = { title = "New chat", scroll = sc, history = {}, n = 0 }
		table.insert(chats, chat)
		openChat(chat)
	end
	newBtn.Activated:Connect(function()
		if busy or #current.history == 0 then return end
		newChat()
	end)

	-- message rendering
	local function scrollDown(chat)
		task.defer(function()
			task.wait()
			chat.scroll.CanvasPosition = Vector2.new(0, 1e6)
		end)
	end
	local function rich(s)
		s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
		local out = {}
		for line in (s .. "\n"):gmatch("(.-)\n") do
			local h = line:match("^#+%s+(.+)$")
			if h then
				line = "<b>" .. h .. "</b>"
			else
				line = line:gsub("^[%-%*]%s+", "• ")
			end
			table.insert(out, line)
		end
		s = table.concat(out, "\n")
		s = s:gsub("%*%*(.-)%*%*", "<b>%1</b>"):gsub("`([^`]+)`", '<font color="#7ee2b8">%1</font>')
		return s
	end
	local function addRow(chat)
		chat.n = chat.n + 1
		local row = N("Frame", { Size = UDim2.new(1, -24, 0, 0), AutomaticSize = AY, BackgroundTransparency = 1, LayoutOrder = chat.n }, chat.scroll)
		N("UISizeConstraint", { MaxSize = Vector2.new(760, math.huge) }, row)
		return row
	end
	local function addUser(chat, text)
		local row = addRow(chat)
		local maxw = math.clamp(main.AbsoluteSize.X - 90, 200, 520)
		local b = label(row, { Text = text, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(0, 0), AutomaticSize = AXY, TextWrapped = true, TextXAlignment = LEFT, BackgroundTransparency = 0, BackgroundColor3 = C.bub })
		N("UISizeConstraint", { MaxSize = Vector2.new(maxw, math.huge) }, b)
		round(b, 16)
		pad(b, 12)
	end
	local function addBot(chat)
		local row = addRow(chat)
		round(N("ImageLabel", { Image = LOGO, Size = UDim2.fromOffset(28, 28), BackgroundTransparency = 1 }, row), 14)
		local col = N("Frame", { Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -40, 0, 0), AutomaticSize = AY, BackgroundTransparency = 1 }, row)
		N("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = LO }, col)
		return col
	end
	local function fill(col, text)
		local pos, isCode, order = 1, false, 0
		while true do
			local a, b = text:find("```", pos, true)
			local chunk = text:sub(pos, (a or (#text + 1)) - 1)
			order = order + 1
			if isCode then
				local lg, body = chunk:match("^([^\n]*)\n(.*)$")
				if not lg or #lg > 20 or lg:find("%s") then lg, body = "code", chunk end
				if lg == "" then lg = "code" end
				body = body:gsub("\n+$", "")
				local blk = N("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, BackgroundColor3 = C.code, LayoutOrder = order }, col)
				round(blk, 10)
				N("UIListLayout", { SortOrder = LO }, blk)
				local cap = label(blk, { Text = lg .. "  ·  tap the code to select it all, then copy", TextSize = 11, TextColor3 = C.mu, Size = UDim2.new(1, 0, 0, 24), TextXAlignment = LEFT, LayoutOrder = 1 })
				N("UIPadding", { PaddingLeft = UDim.new(0, 10) }, cap)
				local tb = N("TextBox", { Text = body, TextEditable = false, ClearTextOnFocus = false, MultiLine = true, TextWrapped = true, Font = Enum.Font.Code, TextSize = 13, TextColor3 = Color3.fromRGB(215, 215, 215), TextXAlignment = LEFT, TextYAlignment = Enum.TextYAlignment.Top, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, LayoutOrder = 2 }, blk)
				N("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, tb)
				tb.Focused:Connect(function()
					tb.CursorPosition = #tb.Text + 1
					tb.SelectionStart = 1
				end)
			else
				chunk = chunk:match("^%s*(.-)%s*$")
				if chunk ~= "" then
					label(col, { Text = rich(chunk), RichText = true, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, TextXAlignment = LEFT, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = order })
				end
			end
			if not a then break end
			pos, isCode = b + 1, not isCode
		end
	end

	local function send(text)
		text = text:match("^%s*(.-)%s*$")
		if busy or text == "" then return end
		local chat = current
		busy = true
		box.Text = ""
		hero.Visible = false
		if #chat.history == 0 then
			chat.title = text:sub(1, 28)
			refreshSide()
		end
		addUser(chat, text)
		table.insert(chat.history, { role = "user", content = text })
		local col = addBot(chat)
		local lbl = label(col, { Text = "", TextColor3 = C.mu, Size = UDim2.new(1, 0, 0, 22), TextXAlignment = LEFT })
		task.spawn(function()
			local i = 0
			while lbl.Parent do
				i = i % 3 + 1
				lbl.Text = T[lang][5] .. string.rep(".", i)
				task.wait(0.4)
			end
		end)
		scrollDown(chat)
		task.spawn(function()
			local ok, res = pcall(function() return remote:InvokeServer("chat", mode, lang, chat.history) end)
			lbl:Destroy()
			if ok and type(res) == "table" and res.ok then
				table.insert(chat.history, { role = "assistant", content = res.text })
				fill(col, res.text)
			else
				table.remove(chat.history) -- drop the failed question so the next try is clean
				local msg = (ok and type(res) == "table" and res.error) or "Could not reach the server."
				label(col, { Text = msg, TextColor3 = C.red, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, TextXAlignment = LEFT })
			end
			busy = false
			scrollDown(chat)
		end)
	end

	box.FocusLost:Connect(function(enter) if enter then send(box.Text) end end)
	sendBtn.Activated:Connect(function() send(box.Text) end)
	for i, b in ipairs(chipBtns) do
		b.Activated:Connect(function() send(T[lang][6][i]) end)
	end

	-- start
	newChat()
	for _, l in ipairs(LANG_LIST) do if l[1] == lang then langBtn.Text = l[2] end end
	refreshMode()
	local t = T[lang]
	heroTitle.Text, heroSub.Text, box.PlaceholderText = t[1], t[2], t[3]
	newBtn.Text = "+  " .. t[4]
	for i, b in ipairs(chipBtns) do b.Text = t[6][i] end
end

------------------------------------------------------------------ START
if RunService:IsServer() then
	server()
else
	client()
end
