function widget:GetInfo()
    return {
        name = "Keybind Editor",
        desc = "A GUI for editing keybinds.\nBind \"togglewidget Keybind Editor\" to set a key to show/hide the menu.",
        author = "MasterBel2",
        date = "April 2023",
        license = "GNU GPL, v2 or later",
        layer = math.huge,
        handler = true
    }
end

------------------------------------------------------------------------------------------------------------
-- MasterFramework
------------------------------------------------------------------------------------------------------------

local MasterFramework
local requiredFrameworkVersion = "Dev"
local key

------------------------------------------------------------------------------------------------------------
-- Imports
------------------------------------------------------------------------------------------------------------

local Spring_GetKeyBindings = Spring.GetKeyBindings

local keyboard

local cachedKeybindings = {}

local lastUpdateModFilter = {}
local modFilter = { alt = false, shift = false, ctrl = false, meta = false }

local keychainDialogKey
local keychainDialog
local currentAction
local currentCommand -- drops the "extra" to allow removing the command
local currentKeybind -- The current (unchanged) keybind; use to revert / remove existing binds
local newKeybind

local keybindFilter
local commandFilter

local categoryElements
local categoryDisclosures

local keybindInterfaceStack

local commandFilterField
local bindFilterField

local keyCodeTypes = {
    unknown = 0,
    modifier = 1,
    operation = 2,
    character = 3
}

local presetDirName = "LuaUI/Config/Hotkeys/"

local keyCodes = VFS.Include("LuaUI/Widgets/keyCodes/sdl1KeyCodes.lua", { keyCodeTypes = keyCodeTypes })
local keyNameToCode = VFS.Include("LuaUI/Widgets/keyCodes/keyCodeNamePairs1.lua")
local keyCodeToName = {}

for keyName, keyCode in pairs(keyNameToCode) do
    keyCodeToName[keyCode] = keyName
end

local defaultPresets = VFS.Include("luaui/configs/keyboard_layouts.lua")
local customPresets = {}

------------------------------------------------------------------------------------------------------------
-- Categories
------------------------------------------------------------------------------------------------------------

local categories = {
    ["Build Unit"] = {},
    ["Build Settings"] = { "buildspacing", "buildfacing" },
    ["Camera"] = { "cameraflip", "set_camera_anchor", "focus_camera_anchor", "moveslow", "movefast", "moveleft", "moveup", "movedown", "moveright", "moveback", "moveforward", "movereset", "moverotate", "movestate", "movetilt", "viewfree", "viewrot", "viewspring", "viewta", "viewfps", "track", "trackmode", "toggleoverview", "togglecammode", "controlunit" },
    ["Chat"] = { "chat", "chatally", "chatall", "chatspec", "chatswitchally", "chatswitchall", "chatswitchspec" },
    ["Commands"] = { "areaattack", "areamex", "attack", "canceltarget", "capture", "cloak", "command_cancel_last", "command_skip_current", "fight", "firestate", "guard", "gatherwait", "loadunits", "manualfire", "manuallaunch", "move", "onoff", "patrol", "reclaim", "repair", "repeat", "restore", "resurrect", "selfd", "settarget", "settargetnoground", "stop", "stopproduction", "unloadunits", "wait", "wantcloak" }, 
    ["Debug"] = { "debug", "debugcolvol", "debugpath" },
    ["Drawing"] = { "drawlabel", "drawinmap" },
    ["Group"] = { "group", "add_to_autogroup", "remove_from_autogroup", "remove_one_unit_from_group", "group0", "group1", "group2", "group3", "group4", "group5", "group6", "group7", "group8", "group9", "groupadd", "groupclear", "groupselect" },
    ["Grid Menu"] = { "gridmenu_category", "gridmenu_cycle_builder", "gridmenu_key", "gridmenu_next_page" },
    ["Selection"] = { "select", "selectbox_all", "selectbox_deselect", "selectbox_idle", "selectbox_mobile", "selectbox_same", "selectloop", "selectloop_add", "selectloop_invert" },
    ["Sound"] = { "snd_volume_increase", "snd_volume_decrease", "mutesound" },
    ["Spec Team"] = { "specteam" },
    ["Speed"] = { "increasespeed", "decreasespeed", "slowdown", "speedup", "singlestep",  },
    ["Unit Travel Time"] = { "unit_travel_enable", "unit_travel_faction", "unit_travel_factory", "unit_travel_tier" },
    ["UI"] = { "luaui", "togglewidget", "enablewidget", "disablewidget", "widgetselector" },
    ["Text Editing"] = { "edit_return", "edit_next_word", "pastetext", "edit_prev_word", "edit_next_char", "edit_prev_char", "edit_next_word", "edit_next_line", "edit_prev_line", "edit_end", "edit_home", "edit_delete", "edit_backspace", "edit_complete", "edit_escape" },
    
    ["Other"] = {}
}

for unitDefName, _ in pairs(UnitDefNames) do
    table.insert(categories["Build Unit"], "buildunit_" .. unitDefName)
end

local commandToCategory = {}

for categoryName, commands in pairs(categories) do
    for _, command in ipairs(commands) do
        commandToCategory[command] = categoryName
    end
end

local categoryDisclosureArrayWithElements
    

------------------------------------------------------------------------------------------------------------
-- Interface Templates
------------------------------------------------------------------------------------------------------------

local function Dialog(titleString, contents, options)
    local dialog
    local dialogKey

    local confirmationDialog

    local dialogTitle = MasterFramework:WrappingText(titleString)
    local optionsStack = MasterFramework:HorizontalStack(
        table.imap(options, function(_, option)
            return MasterFramework:Button(
                MasterFramework:Text(option.name, option.color),
                function()
                    if option.confirmation then
                        confirmationDialog = Dialog(
                            option.confirmation.title,
                            {},
                            {
                                { name = option.name, color = option.color, action = function() option.action(); dialog:Hide() end },
                                { name = "Cancel", color = MasterFramework:Color(1, 1, 1, 0.7), action = function() end }
                            }
                        )
                        confirmationDialog:PresentAbove(dialogKey)
                    else
                        option.action()
                        dialog:Hide()
                    end
                end
            )
        end),
        MasterFramework:AutoScalingDimension(8),
        0
    )

    local editableContents = MasterFramework:VerticalStack(contents, MasterFramework:AutoScalingDimension(8), 0)

    local dialogBody = MasterFramework:VerticalStack( -- TODO: Handling for when there's no  contents?
        { dialogTitle, editableContents, optionsStack },
        MasterFramework:AutoScalingDimension(8),
        0
    )

    dialog = MasterFramework:PrimaryFrame(
        MasterFramework:Background(
            MasterFramework:MarginAroundRect(
                MasterFramework:FrameOfReference(
                    0.5, 0.5,
                    MasterFramework:Background(
                        MasterFramework:MarginAroundRect(
                            dialogBody,
                            MasterFramework:AutoScalingDimension(20),
                            MasterFramework:AutoScalingDimension(20),
                            MasterFramework:AutoScalingDimension(20),
                            MasterFramework:AutoScalingDimension(20)
                        ),
                        { MasterFramework.FlowUIExtensions:Element() },
                        MasterFramework:AutoScalingDimension(5)
                    )
                ),
                MasterFramework:AutoScalingDimension(0),
                MasterFramework:AutoScalingDimension(0),
                MasterFramework:AutoScalingDimension(0),
                MasterFramework:AutoScalingDimension(0)
            ),
            { MasterFramework:Color(0, 0, 0, 0.7) },
            MasterFramework:AutoScalingDimension(5)
        )
    )

    dialog.dialog_body = dialogBody
    dialog.dialog_editableContents = editableContents
    dialog.dialog_optionsStack = optionsStack

    function dialog:PresentAbove(elementKeyBelow)
        local layerRequest = MasterFramework.layerRequest.directlyAbove(elementKeyBelow)
        if dialogKey then
            MasterFramework:MoveElement(dialogKey, layerRequest)
        else
            dialogKey = MasterFramework:InsertElement(dialog, "Dialog", layerRequest)
        end
    end

    function dialog:Hide()
        if dialogKey then
            MasterFramework:RemoveElement(dialogKey)
            dialogKey = nil
        end
        if confirmationDialog then
            confirmationDialog:Hide()
        end
    end

    function dialog:GetKey()
        return dialogKey
    end

    return dialog
end

local function ConfirmationDialog(title, name, color, action)
    return Dialog(title,
        {},
        {
            { name = name, color = color, action = action },
            { name = "Cancel", color = MasterFramework:Color(1, 1, 1, 0.7), action = function() end }
        }
    )
end

------------------------------------------------------------------------------------------------------------
-- Bindings
------------------------------------------------------------------------------------------------------------

local keybindsFileName = "uikeys.txt"
local function save()
    Spring.SendCommands("keysave " .. keybindsFileName)
    -- os.rename("uikeys.tmp", keybindsFileName)
end


-- returns { [1] = { mods = {}, key = <number }, ... }
local function parse(rawString)
    local mods = {
        any = "any",
        ["*"] = "any",
        alt = "alt",
        a = "alt",
        s = "shift",
        shift = "shift",
        m = "meta",
        meta = "meta",
        ctrl = "ctrl",
        c = "ctrl"
    }

    local currentBind = { mods = {} }
    local completedBinds = {}

    local searchIndex = 1
    while searchIndex <= rawString:len() do

        local startIndex, endIndex = rawString:find("[^%+,]+", searchIndex)

        if startIndex ~= searchIndex then -- It's just a bind for "+" or ",". Covers the nil case of startIndex, as searchIndex will never be nil.
            currentBind.key = rawString:sub(searchIndex, searchIndex):lower()
            if rawString:sub(searchIndex + 1, searchIndex + 1) == "," or searchIndex == rawString:len() then
                searchIndex = searchIndex + 2
                table.insert(completedBinds, currentBind)
                currentBind = { mods = {} }
            else
                error("Expected \",\" separator at index " .. searchIndex + 1 .. " in keychain \"" .. rawString .. "\"")
            end
        elseif rawString:sub(endIndex + 1, endIndex + 1) == "+" then -- modifier 
            local possibleMod = rawString:sub(startIndex, endIndex):lower()
            local possibleModMatch = mods[possibleMod]
            if not possibleModMatch then -- parse as a key - e.g. numpad+
                currentBind.key = rawString:sub(startIndex, endIndex + 1):lower()
                table.insert(completedBinds, currentBind)
                currentBind = { mods = {} }
                searchIndex = endIndex + 3
            elseif currentBind.mods[possibleModMatch] then
                error("Repeated modifier \"" .. possibleModMatch .. "\"" .. " in keychain \"" .. rawString .. "\"")
            else
                currentBind.mods[possibleModMatch] = true
                searchIndex = endIndex + 2
            end 
        else -- key, and prepare for next chain
            currentBind.key = rawString:sub(startIndex, endIndex):lower()

            table.insert(completedBinds, currentBind)
            currentBind = { mods = {} }
            
            -- endIndex is either the last character of the string, or rawString[endIndex + 1] == ","; the third option - rawString[endIndex + 1] == "+" has already been covered 
            searchIndex = endIndex + 2
        end
    end

    return completedBinds
end

local function keychainFilterMatch(parsedFilter, parsedBinding)
    for i, filterBind in ipairs(parsedFilter) do
        for mod, _ in pairs(filterBind.mods) do
            local present
            for _, bind in ipairs(parsedBinding) do
                if bind.mods[mod] then
                    present = true
                end
            end
            if not present then
                return false
            end
        end

        if filterBind.key then
            local keyPresent
            for _, bind in ipairs(parsedBinding) do
                if bind.key == filterBind.key or Spring.GetKeyFromScanSymbol(bind.key) == filterBind.key then
                    keyPresent = true
                else
                end
            end
            if not keyPresent then
                return false
            end
        end
    end
    
    return true
end

local function nxor(lhs, rhs)
    return (lhs and rhs) or (not lhs and not rhs)
end

local function refreshKeyboard()
    for code, uiKey in pairs(keyboard.uiKeys) do
        if not (uiKey._keyCode == 0x130 --[[shift]] or uiKey._keyCode == 0x132 --[[ctrl]] or uiKey._keyCode == 0x134 --[[alt]] or uiKey._keyCode == 0x136 --[[meta]] or uiKey._keyCode == 0x20 --[[space/meta]]) then
            uiKey:SetPressed(false)
        end
    end

    for _, binding in ipairs(cachedKeybindings) do
        local keychain = parse(binding.boundWith)
        -- Executive decision: don't worry about multi-key combos
        if #keychain == 1 then
            local bind = keychain[1]
            if nxor(bind.mods.alt, modFilter.alt) and nxor(bind.mods.shift, modFilter.shift) and nxor(bind.mods.ctrl, modFilter.ctrl) and nxor(bind.mods.meta, modFilter.meta) then
                local code = Spring.GetKeyCode(bind.key) or Spring.GetKeyCode(Spring.GetKeyFromScanSymbol(bind.key))
                if code then
                    local uiKey = keyboard.uiKeys[code]
                    if uiKey and not (uiKey._keyCode == 0x130 --[[shift]] or uiKey._keyCode == 0x132 --[[ctrl]] or uiKey._keyCode == 0x134 --[[alt]] or uiKey._keyCode == 0x136 --[[meta]] or uiKey._keyCode == 0x20 --[[space/meta]]) then
                        uiKey:SetPressed(true)
                    end
                end
            end
        end
    end
end

local function refreshBindings()
    local keybindings = Spring_GetKeyBindings()
    keybindings = table.ifilter(keybindings, function(_, binding)
        if (commandFilter and not binding.command:find(commandFilter)) or (keybindFilter and not keychainFilterMatch(parse(keybindFilter), parse(binding.boundWith))) then
            return false
        else 
            return true
        end
    end)
    table.sort(keybindings, function(a, b)
        if a.command == b.command then
            
            if a.boundWith == b.boundWith then
                local aExtra = a.extra or ""
                local bExtra = b.extra or ""
                return aExtra < bExtra
            else 
                return a.boundWith < b.boundWith
            end
        else
            return a.command < b.command
        end
    end)

    cachedKeybindings = keybindings
    refreshKeyboard()

    for _, _categoryElements in pairs(categoryElements) do
        _categoryElements:SetMembers({})
    end

    for _, binding in ipairs(keybindings) do
        local categoryName = commandToCategory[binding.command] or "Other"
        local buttonTitle = "\255\200\200\200Command: \255\255\255\255" .. binding.command .. ((binding.extra == "") and "" or (" " .. binding.extra)) .. "\255\200\200\200, boundWith: \255\255\255\255" .. binding.boundWith

        local categoryMembers = categoryElements[categoryName]:GetMembers()

        table.insert(categoryMembers, MasterFramework:RightClickMenuAnchor(
            MasterFramework:Button(
                MasterFramework:WrappingText(buttonTitle),
                function()
                    currentCommand = binding.command
                    if binding.extra ~= "" then
                        currentAction = binding.command .. " " .. binding.extra
                    else
                        currentAction = binding.command
                    end
                    currentKeybind = binding.boundWith
                    newKeybind = binding.boundWith

                    keychainDialog.dialog_keybindEntry.text:SetString(binding.boundWith)
                    keychainDialog.dialog_actionEntry.text:SetString(currentAction)
                    local keychainDialogMembers = keychainDialog.dialog_body:GetMembers()
                    keychainDialogMembers[4] = nil
                    keychainDialog.dialog_body:SetMembers(keychainDialogMembers)

                    keychainDialog:PresentAbove(key)
                end
            ),
            {
                { title = "Delete", action = function(_, _, _, anchor)
                    local confirmationDialog = ConfirmationDialog(
                        "Are you sure you want to delete binding:\n " .. binding.boundWith .. " " .. binding.command .. " " .. binding.extra,
                        "Delete",
                        MasterFramework:Color(1, 0.3, 0.3, 1),
                        function()
                            Spring.SendCommands("unbind " .. binding.boundWith .. " "  .. binding.command)
                            save()
                            refreshBindings()
                        end
                    )
                    confirmationDialog:PresentAbove(key)
                    anchor:HideMenu()
                end }
            },
            "Binding: " .. binding.boundWith .. " " .. binding.command .. " " .. binding.extra 
        ))

        categoryElements[categoryName]:SetMembers(categoryMembers)
    end

    for categoryName, categoryDisclosure in pairs(categoryDisclosures) do
        categoryDisclosure.disclosure_titleText:SetString(categoryName .. " (" .. #categoryElements[categoryName]:GetMembers() .. ")")
    end

    keybindInterfaceStack:SetMembers(categoryDisclosureArrayWithElements())

    local reloadableWidgets = {'buildmenu', 'ordermenu', 'keybinds'}

    for _, w in pairs(reloadableWidgets) do
        if WG[w] and WG[w].reloadBindings then
            WG[w].reloadBindings()
        end
    end
end

------------------------------------------------------------------------------------------------------------
-- Interface
------------------------------------------------------------------------------------------------------------

local function TakeAvailableHeight(body)
    local cachedHeight
    local cachedAvailableHeight
    return {
        Layout = function(_, availableWidth, availableHeight)
            local width, height = body:Layout(availableWidth, availableHeight)
            cachedHeight = height
            cachedAvailableHeight = math.max(availableHeight, height)
            return width, cachedAvailableHeight
        end,
        Position = function(_, x, y) body:Position(x, y + cachedAvailableHeight - cachedHeight) end
    }
end
local function TakeAvailableWidth(body)
    return {
        Layout = function(_, availableWidth, availableHeight)
            local _, height = body:Layout(availableWidth, availableHeight)
            return availableWidth, height
        end,
        Position = function(_, x, y) body:Position(x, y) end
    }
end

local function Disclosure(title, disclosableView)
    local bodyVisible = false
    local overall
    local wrappedDisclosableView = MasterFramework:MarginAroundRect(
        disclosableView,
        MasterFramework:AutoScalingDimension(8),
        MasterFramework:AutoScalingDimension(0),
        MasterFramework:AutoScalingDimension(0),
        MasterFramework:AutoScalingDimension(0)
    )

    local titleText = MasterFramework:Text(title)
    local button = MasterFramework:Button(
        titleText,
        function() overall:SetBodyVisible(not bodyVisible) end
    )
    overall = MasterFramework:VerticalStack({ button }, MasterFramework:AutoScalingDimension(0), 0)

    function overall:SetBodyVisible(visible)
        if visible then
            overall:SetMembers({ button, wrappedDisclosableView })
        else
            overall:SetMembers({ button })
        end
        bodyVisible = visible
    end

    overall.disclosure_titleText = titleText
    return overall
end

local function KeybindEntry(...) -- TODO: Modifier-only bind support!
    local entry = MasterFramework:TextEntry(...)
    entry.hideSelection = true

    function entry:TextInput() end
    function entry:KeyPress(key, mods, isRepeat, label, utf32char, scanCode, actionList)
        if isRepeat then return end

        newKeybind = ""
        if mods.ctrl then
            newKeybind = newKeybind .. "Ctrl+"
        end
        if mods.shift then
            newKeybind = newKeybind .. "Shift+"
        end
        if mods.alt then
            newKeybind = newKeybind .. "Alt+"
        end
        if mods.meta then
            newKeybind = newKeybind .. "Meta+"
        end

        if keyCodes[key].type == keyCodeTypes.modifier then
            newKeybind = newKeybind:sub(1, newKeybind:len() - 1)
        else
            local keyName = keyCodeToName[key]
            newKeybind = newKeybind .. keyName
        end

        self.text:SetString(newKeybind)

        local conflicts = Spring_GetKeyBindings(newKeybind)

        local dialogMembers = keychainDialog.dialog_body:GetMembers()
        if conflicts and #conflicts > 0 then
            dialogMembers[4] = MasterFramework:Text(
                table.reduce(conflicts, #conflicts .. " Conflict(s)", function(currentValue, nextConflict)
                    return currentValue .. ", " .. nextConflict.command .. " " .. nextConflict.extra .. " (" .. nextConflict.boundWith .. ")"
                end),
                MasterFramework:Color(1, 0.1, 0.1, 1)
            )
        else
            dialogMembers[4] = nil
        end
        keychainDialog.dialogBody:SetMembers(dialogMembers)
    end

    return entry
end

local function KeychainDialog()
    local dialogTitle = MasterFramework:Text("Edit Keybind")
    local actionEntry = MasterFramework:TextEntry("", "Command")
    local keybindEntry = KeybindEntry("", "Bind")

    local dialog = Dialog(
        "Edit Keybind",
        { actionEntry, keybindEntry },
        {
            {
                name = "Okay", 
                color = MasterFramework:Color(0.3, 1, 0.3, 1), 
                action = function()
                    local newAction = keychainDialog.dialog_actionEntry.text.GetRawString()
                    if currentCommand then
                        Spring.SendCommands("unbind " .. currentKeybind .. " " .. currentCommand)
                    end
                    Spring.SendCommands("bind " .. newKeybind .. " " .. newAction)
                    
                    refreshBindings()
                    save()

                    local newCommand = newAction:sub(newAction:find("[^%s]+")) or newAction -- TODO: strip starting spaces
                    categoryDisclosures[commandToCategory[newCommand] or "Other"]:SetBodyVisible(true)
                end
            },
            {   
                name = "Cancel",
                color = MasterFramework.color.white,
                action = function() end
            }
        }
    )

    dialog.dialog_keybindEntry = keybindEntry
    dialog.dialog_actionEntry = actionEntry

    return dialog
end

local debugInfo = {}

function widget:DebugInfo()
    return debugInfo
end

local function loadPresets()
    return {
        { name = "Default", path = "path/to/default.lua" }
    }
end

local function keybindConfigs(fileNames, areImmutable)
    debugInfo[areImmutable] = fileNames
    return table.imap(fileNames, function(_, fileName)
        return {
            name = fileName:match("[%w_%-%./]+/([%w_%-]+)%.txt"),
            path = fileName,
            isImmutable = areImmutable
        }
    end)
end

local function writeStringToFile(string, newLocation, overwrite)
    if not overwrite and VFS.FileExists(newLocation, VFS.RAW) then
        return false
    end

    local dir = newLocation:match("([%w_%-%./]+/)[%w_%-]+%.txt")
    if dir then
        Spring.CreateDir(dir)
    end
    local file = io.open(newLocation, "w")
    file:write(string)
    file:close()

    return true
end

local function copyFile(oldLocation, newLocation, overwrite)
    local string = VFS.LoadFile(oldLocation)
    return writeStringToFile(string, newLocation, overwrite)
end

local function PresetNameEntry()
    local entry = MasterFramework:TextEntry("", "Preset Name", nil, nil, 1)
    function entry:editReturn() end
    entry._TextInput = entry.TextInput
    function entry:TextInput(char)
        if char:find("[%w_%-]") then
            entry:_TextInput(char)
        end
    end

    return entry
end

local function PresetsDialog()

    local immutableConfigs = keybindConfigs(VFS.DirList("luaui/configs/hotkeys/", "*", VFS.MOD), true)
    local mutableConfigs = keybindConfigs(VFS.DirList(presetDirName, "*", VFS.RAW), false)
    
    local presets = table.joinArrays({ mutableConfigs, immutableConfigs })

    local presetsDialog

    local function refreshPresetsDialog()
        presetsDialog:Hide()
        local presetsDialog = PresetsDialog()
        presetsDialog:PresentAbove(key)
    end
    
    local presetStack = MasterFramework:VerticalStack(
        table.imap(presets, function(index, preset)
            local rClickOptions

            if preset.isImmutable then
                rClickOptions = {{ 
                    title = "Duplicate",
                    action = function(_, _, _, anchor)
                        local string = "unbindall\nunbind enter chat\n\n" .. VFS.LoadFile(preset.path)
                        local newPresetName = preset.name .. "_Copy"
    
                        local count = 2
                        while not writeStringToFile(string, presetDirName .. newPresetName .. ".txt", false) do
                            newPresetName = preset.name .. "_Copy_" .. count
                            count = count + 1
                        end
    
                        refreshPresetsDialog()
                        anchor:HideMenu()
                    end
                }}
            else
                rClickOptions = {
                    { 
                        title = "Rename",
                        action = function(_, _, _, anchor)
                            local presetNameEntry = PresetNameEntry("", "Preset Name", nil, nil, 1)
                            local renameDialog = Dialog(
                                "Rename \"" .. preset.name .. "\"",
                                { presetNameEntry },
                                {
                                    {
                                        name = "Rename", 
                                        color = MasterFramework:Color(1, 1, 0.3, 1),
                                        action = function()
                                            local newName = presetNameEntry.text:GetRawString() 
                                            if newName ~= "" and os.rename(preset.path, presetDirName .. presetNameEntry.text:GetRawString() .. ".txt") then
                                                refreshPresetsDialog()
                                            else
                                                Spring.Echo("Not overwriting!")
                                            end
                                        end
                                    },
                                    { name = "Cancel", color = MasterFramework:Color(1, 1, 1, 0.7), action = function() end }
                                }
                            )
                            renameDialog:PresentAbove(presetsDialog:GetKey())
                            anchor:HideMenu()
                        end
                    },
                    { 
                        title = "Duplicate",
                        action = function(_, _, _, anchor)
                            local newPresetName = preset.name .. "_Copy"
                            local count = 2
                            while not copyFile(preset.path, presetDirName .. newPresetName .. ".txt", false) do
                                newPresetName = preset.name .. "_Copy_" .. count
                                count = count + 1
                            end
                            refreshPresetsDialog()
                            anchor:HideMenu()
                        end
                    },
                    { 
                        title = "Delete",
                        action = function(_, _, _, anchor)
                            local confirmationDialog = ConfirmationDialog(
                                "Are you sure you want to delete preset \"" .. preset.name .. "\"?",
                                "Delete",
                                MasterFramework:Color(1, 0.3, 0.3, 1),
                                function()
                                    os.remove(preset.path)
                                    refreshPresetsDialog()
                                end
                            )
                            confirmationDialog:PresentAbove(presetsDialog:GetKey())
                            anchor:HideMenu()
                        end
                    }
                }
            end

            return MasterFramework:RightClickMenuAnchor(
                MasterFramework:Button(
                    MasterFramework:Text(preset.name, preset.isImmutable and MasterFramework:Color(1, 1, 0.3, 1)),
                    function() 
                        local confirmationDialog = ConfirmationDialog(
                            "Loading preset \"" .. preset.name .. "\" will overwrite your current keybinds.\nContinue?",
                            "Continue",
                            MasterFramework:Color(1, 1, 0.3, 1), 
                            function()
                                local string = VFS.LoadFile(preset.path)
                                if preset.isImmutable then
                                    string = "unbindall\nunbind enter chat\n\n" .. string
                                end
                                writeStringToFile(string, keybindsFileName, true)
                                Spring.SendCommands("keyreload")
                                refreshBindings()
                            end
                        )
                        confirmationDialog:PresentAbove(presetsDialog:GetKey())
                    end
                ),
                rClickOptions,
                "Preset \"" .. preset.name .. "\""
            )
        end),
        MasterFramework:AutoScalingDimension(0),
        0.5
    ) 

    presetsDialog = Dialog(
        "Presets",
        {
            presetStack,
            MasterFramework:Button(
                MasterFramework:Text("Save Current Config"),
                function()
                    local presetNameEntry = PresetNameEntry("", "Preset Name", nil, nil, 1)
                    local savePresetDialog = Dialog(
                        "New Preset",
                        { presetNameEntry },
                        {
                            { 
                                name = "Save Config", 
                                color = MasterFramework:Color(0.3, 1, 0.3, 1), 
                                action = function()
                                    local newName = presetNameEntry.text:GetRawString() 
                                    if newName ~= "" and copyFile(keybindsFileName, presetDirName .. presetNameEntry.text:GetRawString() .. ".txt", false) then
                                        refreshPresetsDialog()
                                    else
                                        Spring.Echo("Not overwriting!")
                                    end 
                                end
                            },
                            { name = "Cancel", color = MasterFramework:Color(1, 1, 1, 0.7), action = function() end }
                        }
                    )
                    savePresetDialog:PresentAbove(presetsDialog:GetKey())
                end
            ),
            MasterFramework:Button(
                MasterFramework:Text("Create Empty Config"),
                function()
                    local presetName = "New_Empty"
                    local newPresetName = "New_Empty"
                    local count = 2

                    while VFS.FileExists(presetDirName .. newPresetName .. ".txt") do
                        newPresetName = presetName .. "_" .. count
                        count = count + 1
                    end

                    Spring.CreateDir(presetDirName)
                    local file = io.open(presetDirName .. newPresetName .. ".txt", "w")
                    if not file then 
                        Spring.Echo("Failed to create empty preset!")
                        return
                    end
                    file:write("unbindall // clear engine defaults\nfakemeta space")
                    file:close()
                    refreshPresetsDialog()
                end
            )
        },
        {
            { name = "Done", color = MasterFramework:Color(1, 1, 1, 0.7), action = function() end }
        }
    )

    return presetsDialog
end

------------------------------------------------------------------------------------------------------------
-- Setup/Update/Teardown
------------------------------------------------------------------------------------------------------------

function widget:Initialize()
    MasterFramework = WG["MasterFramework " .. requiredFrameworkVersion]
    if not MasterFramework then
        error("MasterFramework " .. requiredFrameworkVersion .. " not found!")
    end

    table = MasterFramework.table

    local categoryNames = table.mapToArray(categories, function(key, _) return key end)
    table.sort(categoryNames)

    categoryDisclosureArrayWithElements = function()
        return table.imap(table.ifilter(categoryNames, function(_, categoryName) return #categoryElements[categoryName]:GetMembers() > 0 end), function(_, categoryName)
            return categoryDisclosures[categoryName]
        end)
    end

    -- first-time setup

    local barHotkeysWidget = widgetHandler:FindWidget("BAR Hotkeys")
    local alternateChatKeysWidget = widgetHandler:FindWidget("Alternate Chat Keys")

    if barHotkeysWidget or alternateChatKeysWidget then
        if barHotkeysWidget then
            Spring.Echo("[Keybind Editor] \"BAR Hotkeys\" is incompatible!")
        end
        if alternateChatKeysWidget then
            Spring.Echo("[Keybind Editor] \"Alternate Chat Keys\" is incompatible!")
        end

        if VFS.FileExists(keybindsFileName, VFS.RAW) then
            Spring.Echo("[Keybind Editor] We'll back up your existing keys, save your existing config, and take over from the incompatible widgets!")

            local backupKeybindsFileName = "uikeys-backup-" .. os.clock() .. ".txt"
            if os.rename(keybindsFileName, backupKeybindsFileName) then
                Spring.Echo("[Keybind Editor] Backed up current uikeys.txt to data/" .. backupKeybindsFileName)
            else
                Spring.Echo("[Keybind Editor] Failed to back up current uikeys.txt!")
                Spring.Echo("[Keybind Editor] Removing self - please report this issue!")
                widgetHandler:RemoveWidget(self)
                return
            end
        else
            Spring.Echo("[Keybind Editor] We'll save your existing config and take over from the incompatible widgets!")
        end

        Spring.Echo("[Keybind Editor] Taking over keybind management!")
        save()
        
        if barHotkeysWidget then
            Spring.Echo("[Keybind Editor] Disabling \"BAR Hotkeys\" widget!")
            widgetHandler:DisableWidget("BAR Hotkeys")
        end
        if alternateChatKeysWidget then
            Spring.Echo("[Keybind Editor] Disabling \"Alternate Chat Keys\" widget!")
            widgetHandler:DisableWidget("Alternate Chat Keys")
        end

        Spring.SendCommands("keyreload")
    end

    -- Generate Interface

    keychainDialog = KeychainDialog()

    categoryElements = table.imapToTable(categoryNames, function(_, categoryName)
        return categoryName, MasterFramework:VerticalStack({}, MasterFramework:AutoScalingDimension(8), 0)
    end)

    categoryDisclosures = table.imapToTable(categoryNames, function(_, categoryName)
        return categoryName, Disclosure(categoryName, categoryElements[categoryName])
    end)

    keybindInterfaceStack = MasterFramework:VerticalStack(
        categoryDisclosureArrayWithElements(),
        MasterFramework:AutoScalingDimension(0),
        0
    )

    commandFilterField = MasterFramework:TextEntry("", "Type here")
    bindFilterField = KeybindEntry("", "Type here")
    local searchBar = MasterFramework:HorizontalStack(
        {
            MasterFramework:Text("Filter by"),
            MasterFramework:Text("command:"),
            commandFilterField,
            MasterFramework:Text("bind:"),
            bindFilterField,
            MasterFramework:Button(MasterFramework:Text("Clear"), function() commandFilterField.text:SetString(""); bindFilterField.text:SetString("") end)
        },
        MasterFramework:AutoScalingDimension(8),
        0.5
    )

    local function uiKeyAction(uiKey)
        if uiKey._keyCode == 0x130 --[[shift]] or uiKey._keyCode == 0x132 --[[ctrl]] or uiKey._keyCode == 0x134 --[[alt]] or uiKey._keyCode == 0x136 --[[meta]] or uiKey._keyCode == 0x20 --[[space/meta]] then
            local modName = keyCodes[uiKey._keyCode].compressedName:lower()
            modFilter[modName] = not modFilter[modName]
            uiKey:SetPressed(modFilter[modName])

            refreshKeyboard()
        else
            -- todo: present menu of binds to edit

            -- keychainDialog.dialog_keybindEntry.text:SetString("")
            -- keychainDialog.dialog_actionEntry.text:SetString("")
            -- keychainDialog.dialog_body.members[4] = nil

            -- keychainDialog:PresentAbove(key)
        end
    end

    local keyboardTooltip = MasterFramework:Text("")

    local function uiKeyHoverAction(uiKey, isOver)
        if uiKey._keyCode == 0x130 --[[shift]] or uiKey._keyCode == 0x132 --[[ctrl]] or uiKey._keyCode == 0x134 --[[alt]] or uiKey._keyCode == 0x136 --[[meta]] or uiKey._keyCode == 0x20 --[[space/meta]] then
            return 
        end

        if not isOver then
            keyboardTooltip:SetString("")
            return
        end

        local keyset = ""
        if modFilter.ctrl then
            keyset = keyset .. "Ctrl+"
        end
        if modFilter.shift then
            keyset = keyset .. "Shift+"
        end
        if modFilter.alt then
            keyset = keyset .. "Alt+"
        end
        if modFilter.meta then
            keyset = keyset .. "Meta+"
        end

        local keyName = keyCodeToName[uiKey._keyCode]
        if not keyName then return end
        keyset = keyset .. keyName

        keyboardTooltip:SetString(table.concat(table.imap(Spring.GetKeyBindings(keyset), function(_, keyBinding)
            return keyBinding.boundWith .. " " .. keyBinding.command .. " " .. keyBinding.extra
        end), ", "))
    end
    
    keyboard = WG.MasterGUIKeyboard()
    for code, uikey in pairs(keyboard.uiKeys) do
        uikey._uiKey_action = uiKeyAction
        uikey._uiKey_hoverAction = uiKeyHoverAction
    end

    refreshBindings()

    -- keyboard.

    local resizableFrame = MasterFramework:ResizableMovableFrame(
        "Keybind Editor",
        MasterFramework:PrimaryFrame(
            MasterFramework:Background(
                MasterFramework:MarginAroundRect(
                    MasterFramework:VerticalHungryStack(
                        searchBar,
                        TakeAvailableHeight(MasterFramework:VerticalScrollContainer(keybindInterfaceStack)),
                        MasterFramework:VerticalStack(
                            {
                                MasterFramework:HorizontalStack(
                                    {
                                        MasterFramework:Button(
                                            MasterFramework:Text("+"),
                                            function()
                                                keychainDialog.dialog_keybindEntry.text:SetString("")
                                                keychainDialog.dialog_actionEntry.text:SetString("")
                                                local keychainDialogMembers = keychainDialog.dialog_body:GetMembers()
                                                keychainDialogMembers[4] = nil
                                                keychainDialog.dialog_body:SetMembers(keychainDialogMembers)
                    
                                                keychainDialog:PresentAbove(key)
                                            end
                                        ),
                                        MasterFramework:Button(
                                            MasterFramework:Text("Presets"),
                                            function()
                                                local presetsDialog = PresetsDialog()
                                                presetsDialog:PresentAbove(key)
                                            end
                                        ),
                                        keyboardTooltip
                                    }, 
                                    MasterFramework:AutoScalingDimension(8),
                                    0
                                ),
                                keyboard
                            },
                            MasterFramework:AutoScalingDimension(8),
                            0
                        ),
                        0
                    ),
                    MasterFramework:AutoScalingDimension(20),
                    MasterFramework:AutoScalingDimension(20),
                    MasterFramework:AutoScalingDimension(20),
                    MasterFramework:AutoScalingDimension(20)
                ),
                { MasterFramework.FlowUIExtensions:Element() },
                MasterFramework:AutoScalingDimension(5)
            )
        ),
        MasterFramework.viewportWidth * 0.2, MasterFramework.viewportHeight * 0.9,
        MasterFramework.viewportWidth * 0.8, MasterFramework.viewportHeight * 0.8,
        false
    )

    key = MasterFramework:InsertElement(resizableFrame, "Keybinds", MasterFramework.layerRequest.anywhere())
end

function widget:Update()
    -- for key, enabled in pairs(modFilter) do
    --     if lastUpdateModFilter[key] ~= enabled then
    --         -- update keyboard showing

    --         lastUpdateModFilter.alt = modFilter.alt
    --         lastUpdateModFilter.shift = modFilter.shift
    --         lastUpdateModFilter.ctrl = modFilter.ctrl
    --         lastUpdateModFilter.meta = modFilter.meta
    --         break
    --     end
    -- end

    if keybindFilter ~= bindFilterField.text:GetRawString() or commandFilter ~= commandFilterField.text:GetRawString() then
        keybindFilter = bindFilterField.text:GetRawString()
        commandFilter = commandFilterField.text:GetRawString()
        refreshBindings()
    end
end

function widget:Shutdown()
    MasterFramework:RemoveElement(key)
    keychainDialog:Hide()
end