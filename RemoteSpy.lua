--[[
    Remote Spy v1.0
    Complete Single-File Remote Monitoring Tool
    Features: Draggable UI, Minimize/Close, Floating Icon, Remote Hooking
]]

local RemoteSpy = {
    Version = "1.0",
    Logs = {},
    IsMinimized = false,
    LogLimit = 200,
    HookedRemotes = {},
    RemoteData = {}
}

--// Services
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

--// Variables
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local OriginalNamecall
local OriginalIndex
local Mouse = LocalPlayer:GetMouse()

--// UI Config
local WINDOW_SIZE = UDim2.new(0, 600, 0, 400)
local WINDOW_POS = UDim2.new(0.5, -300, 0.5, -200)
local FLOATING_ICON_SIZE = UDim2.new(0, 40, 0, 40)
local BG_COLOR = Color3.fromRGB(20, 20, 20)
local ACCENT_COLOR = Color3.fromRGB(65, 105, 225)
local TEXT_COLOR = Color3.fromRGB(200, 200, 200)

--// ============================================
--// UI Helper Functions
--// ============================================

local function CreateLabel(Parent, Text, Size, Position)
    local Label = Instance.new("TextLabel")
    Label.Text = Text
    Label.TextSize = 12
    Label.TextColor3 = TEXT_COLOR
    Label.BackgroundTransparency = 1
    Label.Font = Enum.Font.GothamMono
    Label.Size = Size
    Label.Position = Position
    Label.Parent = Parent
    return Label
end

local function CreateButton(Parent, Text, Size, Position, Callback)
    local Button = Instance.new("TextButton")
    Button.Text = Text
    Button.TextSize = 12
    Button.TextColor3 = TEXT_COLOR
    Button.BackgroundColor3 = ACCENT_COLOR
    Button.BackgroundTransparency = 0.2
    Button.BorderSizePixel = 0
    Button.Font = Enum.Font.GothamBold
    Button.Size = Size
    Button.Position = Position
    Button.Parent = Parent
    
    Button.MouseButton1Click:Connect(Callback)
    
    Button.MouseEnter:Connect(function()
        Button.BackgroundTransparency = 0.1
    end)
    Button.MouseLeave:Connect(function()
        Button.BackgroundTransparency = 0.2
    end)
    
    return Button
end

local function CreateScrollingFrame(Parent, Size, Position)
    local ScrollFrame = Instance.new("ScrollingFrame")
    ScrollFrame.Size = Size
    ScrollFrame.Position = Position
    ScrollFrame.BackgroundColor3 = BG_COLOR
    ScrollFrame.BackgroundTransparency = 0.3
    ScrollFrame.BorderSizePixel = 1
    ScrollFrame.BorderColor3 = ACCENT_COLOR
    ScrollFrame.ScrollBarThickness = 8
    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    ScrollFrame.Parent = Parent
    
    local UIListLayout = Instance.new("UIListLayout")
    UIListLayout.Padding = UDim.new(0, 4)
    UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    UIListLayout.Parent = ScrollFrame
    
    ScrollFrame.ChildAdded:Connect(function()
        ScrollFrame.CanvasSize = UIListLayout.AbsoluteContentSize + UDim2.new(0, 0, 0, 10)
    end)
    
    return ScrollFrame
end

local function MakeDraggable(Frame)
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    
    local Dragging = false
    local DragStart = nil
    local StartPos = nil
    
    Frame.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Dragging = true
            DragStart = Mouse.Position
            StartPos = Frame.Position
        end
    end)
    
    Frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Dragging = false
        end
    end)
    
    RunService.RenderStepped:Connect(function()
        if Dragging and DragStart then
            local Delta = Mouse.Position - DragStart
            Frame.Position = StartPos + UDim2.new(0, Delta.X, 0, Delta.Y)
        end
    end)
end

--// ============================================
--// Remote Hooking System
--// ============================================

local function GetRemoteInfo(Remote)
    local ClassName = Remote.ClassName
    local Parent = Remote.Parent
    local ParentPath = ""
    
    local Current = Parent
    while Current and Current ~= game do
        ParentPath = Current.Name .. "/" .. ParentPath
        Current = Current.Parent
    end
    
    return {
        Name = Remote.Name,
        Class = ClassName,
        Path = ParentPath,
        Parent = Parent.Name
    }
end

local function HookRemote(Remote, Method)
    if not Remote or RemoteSpy.HookedRemotes[Remote] then return end
    
    local RemoteInfo = GetRemoteInfo(Remote)
    local RemoteId = tostring(Remote):match("0x%x+")
    
    RemoteSpy.RemoteData[RemoteId] = RemoteInfo
    RemoteSpy.HookedRemotes[Remote] = true
    
    if Remote:IsA("RemoteEvent") then
        local OldFireServer = Remote.FireServer
        Remote.FireServer = function(self, ...)
            local Args = {...}
            RemoteSpy:LogRemote({
                Name = Remote.Name,
                Type = "RemoteEvent",
                Method = "FireServer",
                Args = Args,
                Path = RemoteInfo.Path,
                IsOutgoing = true
            })
            return OldFireServer(self, ...)
        end
        
        if Remote:FindFirstChild("OnClientEvent") then
            local OldConnect = Remote.OnClientEvent.Connect
            Remote.OnClientEvent.Connect = function(self, Callback)
                local WrappedCallback = function(...)
                    RemoteSpy:LogRemote({
                        Name = Remote.Name,
                        Type = "RemoteEvent",
                        Method = "OnClientEvent",
                        Args = {...},
                        Path = RemoteInfo.Path,
                        IsOutgoing = false
                    })
                    return Callback(...)
                end
                return OldConnect(self, WrappedCallback)
            end
        end
    elseif Remote:IsA("RemoteFunction") then
        local OldInvokeServer = Remote.InvokeServer
        Remote.InvokeServer = function(self, ...)
            local Args = {...}
            RemoteSpy:LogRemote({
                Name = Remote.Name,
                Type = "RemoteFunction",
                Method = "InvokeServer",
                Args = Args,
                Path = RemoteInfo.Path,
                IsOutgoing = true
            })
            return OldInvokeServer(self, ...)
        end
        
        if Remote:FindFirstChild("OnClientInvoke") then
            local OldConnect = Remote.OnClientInvoke
            Remote.OnClientInvoke = function(...)
                RemoteSpy:LogRemote({
                    Name = Remote.Name,
                    Type = "RemoteFunction",
                    Method = "OnClientInvoke",
                    Args = {...},
                    Path = RemoteInfo.Path,
                    IsOutgoing = false
                })
                return OldConnect(...)
            end
        end
    end
end

local function FindAndHookRemotes()
    local function ScanInstance(Instance, Depth)
        if Depth > 10 then return end
        
        for _, Child in pairs(Instance:GetChildren()) do
            if Child:IsA("RemoteEvent") or Child:IsA("RemoteFunction") then
                HookRemote(Child)
            end
            ScanInstance(Child, Depth + 1)
        end
    end
    
    ScanInstance(game, 0)
end

--// ============================================
--// Logging System
--// ============================================

function RemoteSpy:LogRemote(Data)
    table.insert(self.Logs, {
        Name = Data.Name,
        Type = Data.Type,
        Method = Data.Method,
        Args = Data.Args,
        Path = Data.Path,
        IsOutgoing = Data.IsOutgoing,
        Timestamp = os.time()
    })
    
    if #self.Logs > self.LogLimit then
        table.remove(self.Logs, 1)
    end
    
    if self.OnLogAdded then
        self:OnLogAdded()
    end
end

local function FormatArgument(Arg)
    local ArgType = typeof(Arg)
    
    if ArgType == "string" then
        return "\"" .. tostring(Arg):sub(1, 30) .. "\""
    elseif ArgType == "number" then
        return tostring(Arg)
    elseif ArgType == "boolean" then
        return tostring(Arg)
    elseif ArgType == "Instance" then
        return Arg.ClassName .. ": " .. Arg.Name
    elseif ArgType == "table" then
        return "{...}"
    else
        return ArgType
    end
end

local function FormatArguments(Args)
    local Formatted = {}
    for i, Arg in pairs(Args) do
        if i <= 5 then
            table.insert(Formatted, FormatArgument(Arg))
        end
    end
    return table.concat(Formatted, ", ")
end

--// ============================================
--// UI Creation
--// ============================================

function RemoteSpy:CreateUI()
    --// Main Container
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "RemoteSpyGui"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent = PlayerGui
    
    --// Main Window
    local MainWindow = Instance.new("Frame")
    MainWindow.Name = "MainWindow"
    MainWindow.Size = WINDOW_SIZE
    MainWindow.Position = WINDOW_POS
    MainWindow.BackgroundColor3 = BG_COLOR
    MainWindow.BackgroundTransparency = 0.1
    MainWindow.BorderSizePixel = 2
    MainWindow.BorderColor3 = ACCENT_COLOR
    MainWindow.Parent = ScreenGui
    MainWindow.Active = true
    MainWindow.Draggable = false
    
    MakeDraggable(MainWindow)
    
    --// Title Bar
    local TitleBar = Instance.new("Frame")
    TitleBar.Name = "TitleBar"
    TitleBar.Size = UDim2.new(1, 0, 0, 30)
    TitleBar.BackgroundColor3 = ACCENT_COLOR
    TitleBar.BackgroundTransparency = 0.3
    TitleBar.BorderSizePixel = 0
    TitleBar.Parent = MainWindow
    
    CreateLabel(TitleBar, "Remote Spy v1.0", UDim2.new(0.7, 0, 1, 0), UDim2.new(0, 8, 0, 0))
    
    --// Close Button
    local CloseButton = Instance.new("TextButton")
    CloseButton.Text = "✕"
    CloseButton.TextSize = 16
    CloseButton.TextColor3 = TEXT_COLOR
    CloseButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
    CloseButton.BorderSizePixel = 0
    CloseButton.Size = UDim2.new(0, 30, 1, 0)
    CloseButton.Position = UDim2.new(1, -60, 0, 0)
    CloseButton.Parent = TitleBar
    
    CloseButton.MouseButton1Click:Connect(function()
        MainWindow.Visible = false
        if self.FloatingIcon then
            self.FloatingIcon.Visible = true
        end
    end)
    
    --// Minimize Button
    local MinimizeButton = Instance.new("TextButton")
    MinimizeButton.Text = "−"
    MinimizeButton.TextSize = 16
    MinimizeButton.TextColor3 = TEXT_COLOR
    MinimizeButton.BackgroundColor3 = ACCENT_COLOR
    MinimizeButton.BackgroundTransparency = 0.3
    MinimizeButton.BorderSizePixel = 0
    MinimizeButton.Size = UDim2.new(0, 30, 1, 0)
    MinimizeButton.Position = UDim2.new(1, -30, 0, 0)
    MinimizeButton.Parent = TitleBar
    
    MinimizeButton.MouseButton1Click:Connect(function()
        self.IsMinimized = not self.IsMinimized
        if self.IsMinimized then
            MainWindow.Size = UDim2.new(0, 300, 0, 30)
            MinimizeButton.Text = "□"
        else
            MainWindow.Size = WINDOW_SIZE
            MinimizeButton.Text = "−"
        end
    end)
    
    --// Control Panel
    local ControlPanel = Instance.new("Frame")
    ControlPanel.Name = "ControlPanel"
    ControlPanel.Size = UDim2.new(1, 0, 0, 40)
    ControlPanel.Position = UDim2.new(0, 0, 0, 30)
    ControlPanel.BackgroundTransparency = 1
    ControlPanel.BorderSizePixel = 0
    ControlPanel.Parent = MainWindow
    
    CreateButton(ControlPanel, "Scan & Hook", UDim2.new(0, 120, 1, -8), UDim2.new(0, 8, 0, 4), function()
        FindAndHookRemotes()
    end)
    
    CreateButton(ControlPanel, "Clear Logs", UDim2.new(0, 120, 1, -8), UDim2.new(0, 136, 0, 4), function()
        self.Logs = {}
        self:UpdateLogDisplay()
    end)
    
    CreateButton(ControlPanel, "Auto Scan", UDim2.new(0, 120, 1, -8), UDim2.new(0, 264, 0, 4), function()
        if not self.AutoScanActive then
            self.AutoScanActive = true
            spawn(function()
                while self.AutoScanActive do
                    FindAndHookRemotes()
                    wait(5)
                end
            end)
        else
            self.AutoScanActive = false
        end
    end)
    
    --// Log Display
    local LogContainer = CreateScrollingFrame(
        MainWindow,
        UDim2.new(1, -16, 1, -86),
        UDim2.new(0, 8, 0, 78)
    )
    
    self.LogContainer = LogContainer
    
    --// Status Bar
    local StatusBar = Instance.new("Frame")
    StatusBar.Size = UDim2.new(1, 0, 0, 20)
    StatusBar.Position = UDim2.new(0, 0, 1, -20)
    StatusBar.BackgroundColor3 = ACCENT_COLOR
    StatusBar.BackgroundTransparency = 0.5
    StatusBar.BorderSizePixel = 0
    StatusBar.Parent = MainWindow
    
    local StatusLabel = CreateLabel(StatusBar, "Ready", UDim2.new(1, -8, 1, 0), UDim2.new(0, 8, 0, 0))
    self.StatusLabel = StatusLabel
    
    self.MainWindow = MainWindow
    
    --// Create Floating Icon
    self:CreateFloatingIcon(ScreenGui)
    
    --// Auto update logs
    spawn(function()
        while MainWindow.Parent do
            self:UpdateLogDisplay()
            wait(0.5)
        end
    end)
end

function RemoteSpy:CreateFloatingIcon(ScreenGui)
    local FloatingIcon = Instance.new("TextButton")
    FloatingIcon.Name = "FloatingIcon"
    FloatingIcon.Text = "👁"
    FloatingIcon.TextSize = 20
    FloatingIcon.Size = FLOATING_ICON_SIZE
    FloatingIcon.Position = UDim2.new(0, 10, 1, -60)
    FloatingIcon.BackgroundColor3 = ACCENT_COLOR
    FloatingIcon.BackgroundTransparency = 0.2
    FloatingIcon.BorderSizePixel = 1
    FloatingIcon.BorderColor3 = ACCENT_COLOR
    FloatingIcon.Parent = ScreenGui
    FloatingIcon.ZIndex = 100
    
    MakeDraggable(FloatingIcon)
    
    FloatingIcon.MouseButton1Click:Connect(function()
        FloatingIcon.Visible = false
        self.MainWindow.Visible = true
    end)
    
    self.FloatingIcon = FloatingIcon
end

function RemoteSpy:UpdateLogDisplay()
    local LogContainer = self.LogContainer
    
    --// Clear existing logs
    for _, Child in pairs(LogContainer:GetChildren()) do
        if Child:IsA("UIListLayout") == false then
            Child:Destroy()
        end
    end
    
    --// Add new logs
    for i, Log in pairs(self.Logs) do
        local LogFrame = Instance.new("Frame")
        LogFrame.Size = UDim2.new(1, -16, 0, 60)
        LogFrame.BackgroundColor3 = BG_COLOR
        LogFrame.BackgroundTransparency = 0.5
        LogFrame.BorderSizePixel = 1
        LogFrame.BorderColor3 = Log.IsOutgoing and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(200, 100, 100)
        LogFrame.LayoutOrder = i
        LogFrame.Parent = LogContainer
        
        local Title = CreateLabel(LogFrame, 
            (Log.IsOutgoing and "📤 " or "📥 ") .. Log.Name, 
            UDim2.new(1, -8, 0, 16), 
            UDim2.new(0, 4, 0, 4)
        )
        Title.TextColor3 = Log.IsOutgoing and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(200, 100, 100)
        Title.TextScaled = true
        
        local Method = CreateLabel(LogFrame, 
            "Method: " .. Log.Method, 
            UDim2.new(1, -8, 0, 14), 
            UDim2.new(0, 4, 0, 20)
        )
        Method.TextSize = 10
        
        local ArgsText = FormatArguments(Log.Args)
        local Args = CreateLabel(LogFrame, 
            "Args: " .. ArgsText, 
            UDim2.new(1, -8, 0, 14), 
            UDim2.new(0, 4, 0, 34)
        )
        Args.TextSize = 10
        Args.TextWrapped = true
    end
    
    self.StatusLabel.Text = "Logged: " .. #self.Logs .. " | Hooked: " .. tostring(table.maxn(self.HookedRemotes))
end

--// ============================================
--// Main Execution
--// ============================================

function RemoteSpy:Start()
    print("🔍 Remote Spy Started!")
    self:CreateUI()
    FindAndHookRemotes()
    
    --// Monitor new descendants
    game.DescendantAdded:Connect(function(Descendant)
        if Descendant:IsA("RemoteEvent") or Descendant:IsA("RemoteFunction") then
            HookRemote(Descendant)
        end
    end)
end

--// Start the spy
RemoteSpy:Start()

--// Return module
return RemoteSpy
