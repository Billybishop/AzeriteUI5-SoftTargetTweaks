--[[

	The MIT License (MIT)

	Copyright (c) 2023 Lars Norberg

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.

--]]
local Addon, ns = ...

local RaidWarnings = ns:NewModule("RaidWarnings", "LibMoreEvents-1.0", "AceHook-3.0")
local MFM = ns:GetModule("MovableFramesManager")

-- Lua API
local pairs, unpack = pairs, unpack

-- Addon API
local Colors = ns.Colors
local GetFont = ns.API.GetFont
local GetMedia = ns.API.GetMedia

local defaults = { profile = ns:Merge({
	enabled = true,
	savedPosition = {
		[MFM:GetDefaultLayout()] = {
			scale = ns.API.GetEffectiveScale(),
			[1] = "TOP",
			[2] = 0 * ns.API.GetEffectiveScale(),
			[3] = -340 * ns.API.GetEffectiveScale()
		}
	}
}, ns.moduleDefaults) }

RaidWarnings.InitializeRaidWarningFrame = function(self)

	-- The RaidWarnings have a tendency to look really weird,
	-- as the SetTextHeight method scales the text after it already
	-- has been turned into a bitmap and turned into a texture.
	-- So I'm just going to turn it off. Completely.
	RaidWarningFrame:SetAlpha(.85)
	RaidWarningFrame:SetHeight(80)

	RaidWarningFrame.timings.RAID_NOTICE_MIN_HEIGHT = 26
	RaidWarningFrame.timings.RAID_NOTICE_MAX_HEIGHT = 26
	RaidWarningFrame.timings.RAID_NOTICE_SCALE_UP_TIME = 0
	RaidWarningFrame.timings.RAID_NOTICE_SCALE_DOWN_TIME = 0

	RaidWarningFrameSlot1:SetFontObject(GetFont(26, true, "Chat"))
	RaidWarningFrameSlot1:SetShadowColor(0, 0, 0, .5)
	RaidWarningFrameSlot1:SetWidth(760)
	RaidWarningFrameSlot1.SetTextHeight = function() end

	RaidWarningFrameSlot2:SetFontObject(GetFont(26, true, "Chat"))
	RaidWarningFrameSlot2:SetShadowColor(0, 0, 0, .5)
	RaidWarningFrameSlot2:SetWidth(760)
	RaidWarningFrameSlot2.SetTextHeight = function() end

	self.frame = RaidWarningFrame

end

RaidWarnings.InitializeMovableFrameAnchor = function(self)

	local anchor = MFM:RequestAnchor()
	anchor:SetTitle(CHAT_MSG_RAID_WARNING)
	anchor:SetScalable(true)
	anchor:SetMinMaxScale(.25, 2.5, .05)
	anchor:SetSize(760, 80)
	anchor:SetPoint(unpack(defaults.profile.savedPosition[MFM:GetDefaultLayout()]))
	anchor:SetScale(defaults.profile.savedPosition[MFM:GetDefaultLayout()].scale)
	anchor:SetDefaultScale(ns.API.GetEffectiveScale)
	anchor.PreUpdate = function() self:UpdateAnchor() end
	anchor.frameOffsetX = 0
	anchor.frameOffsetY = 0
	anchor.framePoint = "CENTER"

	self.anchor = anchor
end

RaidWarnings.UpdatePositionAndScale = function(self)
	if (not self.frame) then return end

	local config = self.db.profile.savedPosition[MFM:GetLayout()]

	self.frame:SetScale(config.scale)
	self.frame:ClearAllPoints()
	self.frame:SetPoint(config[1], UIParent, config[1], config[2]/config.scale, config[3]/config.scale)
end

RaidWarnings.UpdateAnchor = function(self)
	local config = self.db.profile.savedPosition[MFM:GetLayout()]
	self.anchor:SetScale(config.scale)
	self.anchor:ClearAllPoints()
	self.anchor:SetPoint(config[1], UIParent, config[1], config[2], config[3])
end

RaidWarnings.OnEvent = function(self, event, ...)
	if (event == "PLAYER_ENTERING_WORLD") then
		self.incombat = nil
		self:UpdatePositionAndScale()

	elseif (event == "PLAYER_REGEN_ENABLED") then
		if (InCombatLockdown()) then return end
		self.incombat = nil

	elseif (event == "PLAYER_REGEN_DISABLED") then
		self.incombat = true

	elseif (event == "MFM_LayoutsUpdated") then
		local LAYOUT = ...

		if (not self.db.profile.savedPosition[LAYOUT]) then
			self.db.profile.savedPosition[LAYOUT] = ns:Merge({}, defaults.profile.savedPosition[MFM:GetDefaultLayout()])
		end

		self:UpdatePositionAndScale()
		self:UpdateAnchor()

	elseif (event == "MFM_LayoutDeleted") then
		local LAYOUT = ...

		self.db.profile.savedPosition[LAYOUT] = nil

	elseif (event == "MFM_PositionUpdated") then
		local LAYOUT, anchor, point, x, y = ...

		if (anchor ~= self.anchor) then return end

		self.db.profile.savedPosition[LAYOUT][1] = point
		self.db.profile.savedPosition[LAYOUT][2] = x
		self.db.profile.savedPosition[LAYOUT][3] = y

		self:UpdatePositionAndScale()

	elseif (event == "MFM_AnchorShown") then
		local LAYOUT, anchor, point, x, y = ...

		if (anchor ~= self.anchor) then return end

	elseif (event == "MFM_ScaleUpdated") then
		local LAYOUT, anchor, scale = ...

		if (anchor ~= self.anchor) then return end

		self.db.profile.savedPosition[LAYOUT].scale = scale
		self:UpdatePositionAndScale()

	elseif (event == "MFM_Dragging") then
		if (not self.incombat) then
			if (select(2, ...) ~= self.anchor) then return end

			self:OnEvent("MFM_PositionUpdated", ...)
		end
	end
end

RaidWarnings.OnInitialize = function(self)
	self.db = ns.db:RegisterNamespace("RaidWarnings", defaults)

	self:SetEnabledState(self.db.profile.enabled)

	-- Register the available layout names
	-- with the movable frames manager.
	MFM:RegisterPresets(self.db.profile.savedPosition)

	self:InitializeRaidWarningFrame()
	self:InitializeMovableFrameAnchor()
end

RaidWarnings.OnEnable = function(self)

	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEvent")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEvent")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnEvent")

	ns.RegisterCallback(self, "MFM_LayoutDeleted", "OnEvent")
	ns.RegisterCallback(self, "MFM_LayoutsUpdated", "OnEvent")
	ns.RegisterCallback(self, "MFM_PositionUpdated", "OnEvent")
	ns.RegisterCallback(self, "MFM_AnchorShown", "OnEvent")
	ns.RegisterCallback(self, "MFM_ScaleUpdated", "OnEvent")
	ns.RegisterCallback(self, "MFM_Dragging", "OnEvent")
end
