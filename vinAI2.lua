
--[[
    VIN AI
    Executor-compatible Chat UI
    Created by: Vincent / Evilmorty_143

    Heavy mode: Gemini API
    Medium/Light: Local demo responses
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local GUI_PARENT = (gethui and gethui()) or game:GetService("CoreGui")

-- Prevent duplicate GUIs
pcall(function()
    local old = GUI_PARENT:FindFirstChild("VINAI_GUI")
    if old then old:Destroy() end
end)

local CONFIG = {
    NAME = "VIN AI",
    VERSION = "1.0",
    UNLOCK_CODE = "5201314",
    MODEL = "gemini-2.5-flash",
    API_URL = "https://generativelanguage.googleapis.com/v1beta/models/",
    LOGO = "rbxassetid://72694888911234"
}

local COLORS = {
    Background = Color3.fromRGB(18, 18, 20),
    Sidebar = Color3.fromRGB(24, 24, 27),
    Panel = Color3.fromRGB(32, 32, 36),
    Input = Color3.fromRGB(42, 42, 47),
    Text = Color3.fromRGB(240, 240, 245),
    Muted = Color3.fromRGB(155, 155, 165),
    Red = Color3.fromRGB(220, 45, 55),
    Border = Color3.fromRGB(55, 55, 62)
}

local function create(class, props, parent)
    local obj = Instance.new(class)
    for key, value in pairs(props or {}) do
        obj[key] = value
    end
    obj.Parent = parent
    return obj
end

local function corner(parent, radius)
    create("UICorner", {
        CornerRadius = UDim.new(0, radius or 10)
    }, parent)
end

local function stroke(parent, color)
    create("UIStroke", {
        Color = color or COLORS.Border,
        Thickness = 1,
        Transparency = 0.25
    }, parent)
end

local function button(parent, text, size, position)
    local b = create("TextButton", {
        Size = size,
        Position = position,
        BackgroundColor3 = COLORS.Panel,
        Text = text,
        TextColor3 = COLORS.Text,
        TextSize = 14,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = true
    }, parent)
    corner(b, 9)
    return b
end

local Screen = create("ScreenGui", {
    Name = "VINAI_GUI",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, GUI_PARENT)

local Main = create("Frame", {
    Name = "Main",
    Size = UDim2.new(0, 760, 0, 490),
    Position = UDim2.new(0.5, -380, 0.5, -245),
    BackgroundColor3 = COLORS.Background,
    BorderSizePixel = 0
}, Screen)
corner(Main, 14)
stroke(Main)

-- Responsive sizing
local function resize()
    local camera = workspace.CurrentCamera
    if not camera then return end

    local viewport = camera.ViewportSize
    if viewport.X < 650 then
        Main.Size = UDim2.new(0.96, 0, 0.88, 0)
        Main.Position = UDim2.new(0.02, 0, 0.06, 0)
    else
        Main.Size = UDim2.new(0, 760, 0, 490)
        Main.Position = UDim2.new(0.5, -380, 0.5, -245)
    end
end
resize()

-- Dragging
local dragging = false
local dragStart, startPosition

Main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = Main.Position
    end
end)

game:GetService("UserInputService").InputChanged:Connect(function(input)
    if dragging and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)

game:GetService("UserInputService").InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- Sidebar
local Sidebar = create("Frame", {
    Size = UDim2.new(0, 190, 1, 0),
    BackgroundColor3 = COLORS.Sidebar,
    BorderSizePixel = 0
}, Main)
corner(Sidebar, 14)

local Brand = create("TextLabel", {
    Position = UDim2.new(0, 17, 0, 15),
    Size = UDim2.new(1, -30, 0, 35),
    BackgroundTransparency = 1,
    Text = "◈ VIN AI",
    TextColor3 = COLORS.Text,
    TextSize = 21,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left
}, Sidebar)

local NewChat = button(
    Sidebar, "+  New chat",
    UDim2.new(1, -24, 0, 38),
    UDim2.new(0, 12, 0, 65)
)
NewChat.BackgroundColor3 = COLORS.Panel

local HistoryTitle = create("TextLabel", {
    Position = UDim2.new(0, 15, 0, 120),
    Size = UDim2.new(1, -25, 0, 20),
    BackgroundTransparency = 1,
    Text = "RECENT CHATS",
    TextColor3 = COLORS.Muted,
    TextSize = 10,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left
}, Sidebar)

local History = create("ScrollingFrame", {
    Position = UDim2.new(0, 10, 0, 145),
    Size = UDim2.new(1, -20, 1, -205),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 2,
    CanvasSize = UDim2.new()
}, Sidebar)

local HistoryLayout = create("UIListLayout", {
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder
}, History)

local SettingsButton = button(
    Sidebar, "⚙  Settings",
    UDim2.new(1, -24, 0, 36),
    UDim2.new(0, 12, 1, -48)
)

-- Main chat area
local ChatArea = create("Frame", {
    Position = UDim2.new(0, 190, 0, 0),
    Size = UDim2.new(1, -190, 1, 0),
    BackgroundTransparency = 1
}, Main)

local Topbar = create("Frame", {
    Size = UDim2.new(1, 0, 0, 55),
    BackgroundTransparency = 1
}, ChatArea)

local ModeLabel = create("TextLabel", {
    Position = UDim2.new(0, 18, 0, 0),
    Size = UDim2.new(0.7, 0, 1, 0),
    BackgroundTransparency = 1,
    Text = "VIN AI  •  LIGHT",
    TextColor3 = COLORS.Text,
    TextSize = 15,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left
}, Topbar)

local Close = button(
    Topbar, "×",
    UDim2.new(0, 32, 0, 32),
    UDim2.new(1, -45, 0, 10)
)
Close.TextSize = 20
Close.MouseButton1Click:Connect(function()
    Screen:Destroy()
end)

local Messages = create("ScrollingFrame", {
    Position = UDim2.new(0, 12, 0, 58),
    Size = UDim2.new(1, -24, 1, -135),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    CanvasSize = UDim2.new()
}, ChatArea)

local MessageLayout = create("UIListLayout", {
    Padding = UDim.new(0, 12),
    SortOrder = Enum.SortOrder.LayoutOrder
}, Messages)

local function updateCanvas()
    task.wait()
    Messages.CanvasSize = UDim2.new(
        0, 0, 0, MessageLayout.AbsoluteContentSize.Y + 20
    )
    Messages.CanvasPosition = Vector2.new(
        0, math.max(0, MessageLayout.AbsoluteContentSize.Y)
    )
end

local function addMessage(role, content)
    local isUser = role == "user"

    local holder = create("Frame", {
        Size = UDim2.new(1, -10, 0, 50),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1
    }, Messages)

    local bubble = create("Frame", {
        Size = UDim2.new(isUser and 0.82 or 1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = isUser and UDim2.new(0.18, 0, 0, 0)
            or UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = isUser and COLORS.Panel
            or COLORS.Background,
        BorderSizePixel = 0
    }, holder)
    corner(bubble, 10)

    local label = create("TextLabel", {
        Position = UDim2.new(0, 12, 0, 10),
        Size = UDim2.new(1, -24, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = content,
        TextColor3 = COLORS.Text,
        TextSize = 13,
        Font = Enum.Font.Code,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top
    }, bubble)

    local padding = create("UIPadding", {
        PaddingBottom = UDim.new(0, 10)
    }, bubble)

    updateCanvas()
    return holder
end

-- Composer
local Composer = create("Frame", {
    Position = UDim2.new(0, 12, 1, -67),
    Size = UDim2.new(1, -24, 0, 52),
    BackgroundColor3 = COLORS.Input,
    BorderSizePixel = 0
}, ChatArea)
corner(Composer, 13)
stroke(Composer)

local Input = create("TextBox", {
    Position = UDim2.new(0, 13, 0, 0),
    Size = UDim2.new(1, -65, 1, 0),
    BackgroundTransparency = 1,
    Text = "",
    PlaceholderText = "Message VIN AI...",
    PlaceholderColor3 = COLORS.Muted,
    TextColor3 = COLORS.Text,
    TextSize = 13,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
    MultiLine = true
}, Composer)

local Send = button(
    Composer, "↑",
    UDim2.new(0, 38, 0, 36),
    UDim2.new(1, -45, 0, 8)
)
Send.BackgroundColor3 = COLORS.Red
Send.TextSize = 20

-- State
local Mode = "LIGHT"
local ApiKey = ""
local Unlocked = false
local Busy = false
local ChatHistory = {}

local function localResponse(prompt)
    local lower = string.lower(prompt)

    if string.find(lower, "hello") or string.find(lower, "hi") then
        return "Hello! I'm VIN AI. How can I help you today?"
    elseif string.find(lower, "loadstring") then
        return "A loadstring loads and executes Lua code from a string. Only use trusted sources."
    elseif string.find(lower, "roblox") then
        return "Roblox uses Luau, a Lua-derived scripting language. I can help explain its syntax and APIs."
    elseif string.find(lower, "print") then
        return "In Luau, print() outputs a value to the developer console.\n\nExample:\nprint('Hello, world!')"
    end

    return "I'm running in " .. Mode .. " mode. This is a local demo response, not a generated AI answer. HEAVY mode connects to Gemini."
end

local function getRequestFunction()
    if typeof(request) == "function" then
        return request
    elseif typeof(http_request) == "function" then
        return http_request
    elseif syn and typeof(syn.request) == "function" then
        return syn.request
    end
    return nil
end

local function askGemini(prompt)
    local req = getRequestFunction()
    if not req then
        return "Your executor does not expose a supported HTTP request function."
    end

    local url = CONFIG.API_URL .. CONFIG.MODEL
        .. ":generateContent?key=" .. ApiKey

    local body = {
        contents = {
            {
                role = "user",
                parts = {
                    { text = prompt }
                }
            }
        },
        systemInstruction = {
            parts = {
                {
                    text = "You are VIN AI, a helpful assistant focused on Roblox Luau, programming, and general questions. Format code clearly. Never claim code was tested if it was not."
                }
            }
        },
        generationConfig = {
            temperature = 0.7,
            maxOutputTokens = 4096
        }
    }

    local success, response = pcall(function()
        return req({
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(body)
        })
    end)

    if not success then
        return "Request failed: " .. tostring(response)
    end

    if not response or response.StatusCode < 200
        or response.StatusCode >= 300 then
        return "Gemini API error: " ..
            tostring(response and response.StatusCode or "Unknown")
    end

    local decodedSuccess, decoded = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)

    if not decodedSuccess then
        return "Could not decode Gemini's response."
    end

    local candidate = decoded.candidates
        and decoded.candidates[1]

    local parts = candidate
        and candidate.content
        and candidate.content.parts

    if not parts then
        return "Gemini returned an empty response."
    end

    local result = ""
    for _, part in ipairs(parts) do
        if part.text then
            result ..= part.text
        end
    end

    return result ~= "" and result or "No response text received."
end

-- History
local function addHistory(title)
    local item = button(
        History,
        title:sub(1, 24),
        UDim2.new(1, 0, 0, 32),
        UDim2.new()
    )
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextSize = 11
    item.MouseButton1Click:Connect(function()
        -- History entries are labels for this session.
    end)

    task.wait()
    History.CanvasSize = UDim2.new(
        0, 0, 0, HistoryLayout.AbsoluteContentSize.Y + 10
    )
end

local function sendMessage()
    local prompt = Input.Text
    if prompt:gsub("%s", "") == "" or Busy then return end

    Busy = true
    Input.Text = ""

    addMessage("user", prompt)
    addHistory(prompt)

    table.insert(ChatHistory, {
        role = "user",
        text = prompt
    })

    local reply
    if Mode == "HEAVY" then
        if not Unlocked or ApiKey == "" then
            reply = "HEAVY mode is locked. Open Settings to unlock it and enter your Gemini API key."
        else
            reply = "Thinking..."
            local holder = addMessage("assistant", reply)

            task.spawn(function()
                local result = askGemini(prompt)
                if holder and holder.Parent then
                    holder:Destroy()
                end
                addMessage("assistant", result)
                table.insert(ChatHistory, {
                    role = "assistant",
                    text = result
                })
                Busy = false
            end)
            return
        end
    else
        reply = localResponse(prompt)
    end

    addMessage("assistant", reply)
    table.insert(ChatHistory, {
        role = "assistant",
        text = reply
    })

    Busy = false
end

Send.MouseButton1Click:Connect(sendMessage)

Input.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        sendMessage()
    end
end)

-- Mode selector
local ModeButton = button(
    Sidebar, "Mode: LIGHT",
    UDim2.new(1, -24, 0, 36),
    UDim2.new(0, 12, 0, 355)
)

local modes = { "LIGHT", "MEDIUM", "HEAVY" }
local modeIndex = 1

ModeButton.MouseButton1Click:Connect(function()
    modeIndex = modeIndex % #modes + 1
    Mode = modes[modeIndex]
    ModeButton.Text = "Mode: " .. Mode
    ModeLabel.Text = "VIN AI  •  " .. Mode
end)

-- Settings window
local Settings = create("Frame", {
    Visible = false,
    Size = UDim2.new(0, 330, 0, 280),
    Position = UDim2.new(0.5, -165, 0.5, -140),
    BackgroundColor3 = COLORS.Sidebar,
    BorderSizePixel = 0,
    ZIndex = 10
}, Main)
corner(Settings, 12)
stroke(Settings)

local SettingsTitle = create("TextLabel", {
    Position = UDim2.new(0, 15, 0, 10),
    Size = UDim2.new(1, -50, 0, 30),
    BackgroundTransparency = 1,
    Text = "VIN AI Settings",
    TextColor3 = COLORS.Text,
    TextSize = 17,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 11
}, Settings)

local SettingsClose = button(
    Settings, "×",
    UDim2.new(0, 30, 0, 30),
    UDim2.new(1, -40, 0, 8)
)
SettingsClose.ZIndex = 11
SettingsClose.MouseButton1Click:Connect(function()
    Settings.Visible = false
end)

local UnlockInput = create("TextBox", {
    Position = UDim2.new(0, 15, 0, 65),
    Size = UDim2.new(1, -30, 0, 38),
    BackgroundColor3 = COLORS.Input,
    Text = "",
    PlaceholderText = "Heavy mode unlock code",
    TextColor3 = COLORS.Text,
    PlaceholderColor3 = COLORS.Muted,
    TextSize = 12,
    Font = Enum.Font.Gotham,
    ClearTextOnFocus = false,
    ZIndex = 11
}, Settings)
corner(UnlockInput, 8)

local UnlockButton = button(
    Settings, "Unlock HEAVY mode",
    UDim2.new(1, -30, 0, 35),
    UDim2.new(0, 15, 0, 110)
)
UnlockButton.ZIndex = 11

local KeyInput = create("TextBox", {
    Position = UDim2.new(0, 15, 0, 160),
    Size = UDim2.new(1, -30, 0, 38),
    BackgroundColor3 = COLORS.Input,
    Text = "",
    PlaceholderText = "Gemini API key",
    TextColor3 = COLORS.Text,
    PlaceholderColor3 = COLORS.Muted,
    TextSize = 12,
    Font = Enum.Font.Gotham,
    ClearTextOnFocus = false,
    ZIndex = 11
}, Settings)
corner(KeyInput, 8)

local SaveKey = button(
    Settings, "Save API key",
    UDim2.new(1, -30, 0, 35),
    UDim2.new(0, 15, 0, 205)
)
SaveKey.ZIndex = 11

local SettingsStatus = create("TextLabel", {
    Position = UDim2.new(0, 15, 1, -27),
    Size = UDim2.new(1, -30, 0, 20),
    BackgroundTransparency = 1,
    Text = "API key is kept in this session only.",
    TextColor3 = COLORS.Muted,
    TextSize = 10,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 11
}, Settings)

UnlockButton.MouseButton1Click:Connect(function()
    if UnlockInput.Text == CONFIG.UNLOCK_CODE then
        Unlocked = true
        SettingsStatus.Text = "HEAVY mode unlocked."
        SettingsStatus.TextColor3 = Color3.fromRGB(100, 220, 130)
    else
        SettingsStatus.Text = "Incorrect unlock code."
        SettingsStatus.TextColor3 = COLORS.Red
    end
end)

SaveKey.MouseButton1Click:Connect(function()
    if KeyInput.Text ~= "" then
        ApiKey = KeyInput.Text
        SettingsStatus.Text = "API key saved for this session."
        SettingsStatus.TextColor3 = Color3.fromRGB(100, 220, 130)
    end
end)

SettingsButton.MouseButton1Click:Connect(function()
    Settings.Visible = not Settings.Visible
end)

NewChat.MouseButton1Click:Connect(function()
    for _, child in ipairs(Messages:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    table.clear(ChatHistory)
    addMessage("assistant", "New chat started. How can I help?")
end)

-- Welcome screen
addMessage(
    "assistant",
    "Welcome to VIN AI.\n\nYour Roblox Luau assistant is ready.\n\nSelect a mode and send a message to begin."
)

print("[VIN AI] Loaded successfully.")
