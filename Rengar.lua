
if FileExist(COMMON_PATH .. "HPred.lua") then
	require 'HPred'
else
	PrintChat("HPred.lua missing!")
end
if FileExist(COMMON_PATH .. "TPred.lua") then
	require 'TPred'
else
	PrintChat("TPred.lua missing!")
end

require "PremiumPrediction"

function EnemiesAround(pos, range)
	local N = 0
	for i = 1,Game.HeroCount() do
		local hero = Game.Hero(i)
		if ValidTarget(hero,range + hero.boundingRadius) and hero.isEnemy and not hero.dead then
			N = N + 1
		end
	end
	return N
end



function GetDistanceSqr(Pos1, Pos2)
	local Pos2 = Pos2 or myHero.pos
	local dx = Pos1.x - Pos2.x
	local dz = (Pos1.z or Pos1.y) - (Pos2.z or Pos2.y)
	return dx^2 + dz^2
end

function GetDistance(Pos1, Pos2)
	return math.sqrt(GetDistanceSqr(Pos1, Pos2))
end

function GetEnemyHeroes()
	EnemyHeroes = {}
	for i = 1, Game.HeroCount() do
		local Hero = Game.Hero(i)
		if Hero.isEnemy then
			table.insert(EnemyHeroes, Hero)
		end
	end
	return EnemyHeroes
end



function GetItemSlot(unit, id)
	for i = ITEM_1, ITEM_7 do
		if unit:GetItemData(i).itemID == id then
			return i
		end
	end
	return 0
end

function GetPercentHP(unit)
	return 100*unit.health/unit.maxHealth
end

function GetTarget(range)
	if _G.SDK then
		return _G.SDK.TargetSelector:GetTarget(range, _G.SDK.DAMAGE_TYPE_PHYSICAL);
	else
		return _G.GOS:GetTarget(range,"AD")
	end
end

function GotBuff(unit, buffname)
	for i = 0, unit.buffCount do
		local buff = unit:GetBuff(i)
		if buff.name == buffname and buff.count > 0 then 
			return buff.count
		end
	end
	return 0
end

function IsImmobile(unit)
	for i = 0, unit.buffCount do
		local buff = unit:GetBuff(i)
		if buff and (buff.type == 5 or buff.type == 11 or buff.type == 18 or buff.type == 22 or buff.type == 24 or buff.type == 28 or buff.type == 29 or buff.name == "recall") and buff.count > 0 then
			return true
		end
	end
	return false
end



function IsReady(spell)
	return Game.CanUseSpell(spell) == 0
end



function Mode()
	if _G.SDK then
		if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
			return "Combo"
		elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] then
			return "Harass"
		elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] then
			return "LaneClear"
		elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_FLEE] then
			return "Flee"
		end
	else
		return GOS.GetMode()
	end
end

function ValidTarget(target, range)
	range = range and range or math.huge
	return target ~= nil and target.valid and target.visible and not target.dead and target.distance <= range
end

function VectorPointProjectionOnLineSegment(v1, v2, v)
	local cx, cy, ax, ay, bx, by = v.x, (v.z or v.y), v1.x, (v1.z or v1.y), v2.x, (v2.z or v2.y)
	local rL = ((cx - ax) * (bx - ax) + (cy - ay) * (by - ay)) / ((bx - ax) ^ 2 + (by - ay) ^ 2)
	local pointLine = { x = ax + rL * (bx - ax), y = ay + rL * (by - ay) }
	local rS = rL < 0 and 0 or (rL > 1 and 1 or rL)
	local isOnSegment = rS == rL
	local pointSegment = isOnSegment and pointLine or {x = ax + rS * (bx - ax), y = ay + rS * (by - ay)}
	return pointSegment, pointLine, isOnSegment
end

class "Rengar"

local HeroIcon = "https://www.mobafire.com/images/avatars/yasuo-classic.png"
local IgniteIcon = "http://pm1.narvii.com/5792/0ce6cda7883a814a1a1e93efa05184543982a1e4_hq.jpg"
local QIcon = "https://vignette.wikia.nocookie.net/leagueoflegends/images/e/e5/Steel_Tempest.png"
local Q3Icon = "https://vignette.wikia.nocookie.net/leagueoflegends/images/4/4b/Steel_Tempest_3.png"
local WIcon = "https://vignette.wikia.nocookie.net/leagueoflegends/images/6/61/Wind_Wall.png"
local EIcon = "https://vignette.wikia.nocookie.net/leagueoflegends/images/f/f8/Sweeping_Blade.png"
local RIcon = "https://vignette.wikia.nocookie.net/leagueoflegends/images/c/c6/Last_Breath.png"
local ETravel = true
local IS = {}

function Rengar:Menu()
	self.Menu = MenuElement({type = MENU, id = "Rengar", name = "Rengar"})
	self.Menu:MenuElement({id = "ClearMode", name = "Clear", type = MENU})
	self.Menu.ClearMode:MenuElement({id = "UseQ", name = "Q: Leap Strike", value = true})
	self.Menu.ClearMode:MenuElement({id = "UseW", name = "W: Empower", value = true})
	self.Menu.ClearMode:MenuElement({id = "UseE", name = "E: Counter Strike", value = true})
	self.Menu.ClearMode:MenuElement({id = "clearActive", name = "Clear key", key = string.byte("V")})

end


function Rengar:Spells()
	RengarW = {range = 400}
	RengarE = {range = 1000, width = 80, speed = 1500, delay = 0.01,collision = true, aoe = false, type = "line"}
	self.e = {Type = _G.SPELLTYPE_LINE, Range = 1000, Radius = 40, Speed = 1500, Collision = true, MaxCollision = 1, CollisionTypes = {0, 2, 3}}
	spellData = {speed = 1500, range = 1000, delay = 0.01, radius = 40, collision = {"minion"}, type = "linear"}
end

function Rengar:__init()
	Item_HK = {}
	self:Spells()
	self:Menu()
	EmpowerCast = false
	Callback.Add("Tick", function() self:Tick() end)
	Callback.Add("Draw", function() self:Draw() end)
end

function Rengar:Tick()
	if myHero.dead or Game.IsChatOpen() == true then return end
	target = GetTarget(1400)	
	Item_HK[ITEM_1] = HK_ITEM_1
	Item_HK[ITEM_2] = HK_ITEM_2
	Item_HK[ITEM_3] = HK_ITEM_3
	Item_HK[ITEM_4] = HK_ITEM_4
	Item_HK[ITEM_5] = HK_ITEM_5
	Item_HK[ITEM_6] = HK_ITEM_6
	Item_HK[ITEM_7] = HK_ITEM_7
	self:Items1()
	self:Items2()
	self:Combo()
	self:Harass()

	if self.Menu.ClearMode.clearActive:Value() then
		--IsJump()
		self:JungleClear()
	end


end


function Rengar:Items1()
	if EnemiesAround(myHero, 1000) >= 1 then
		       if GetItemSlot(myHero, 3074) > 0 and ValidTarget(target, 300) then
					if myHero:GetSpellData(GetItemSlot(myHero, 3074)).currentCd == 0 then
						Control.CastSpell(Item_HK[GetItemSlot(myHero, 3074)], target)
					end
				end

				if GetItemSlot(myHero, 3077) > 0 and ValidTarget(target, 300) then
					if myHero:GetSpellData(GetItemSlot(myHero, 3077)).currentCd == 0 then
						Control.CastSpell(Item_HK[GetItemSlot(myHero, 3077)], target)
					end
				end
		
			
				if GetItemSlot(myHero, 3144) > 0 and ValidTarget(target, 550) then
					if myHero:GetSpellData(GetItemSlot(myHero, 3144)).currentCd == 0 then
						Control.CastSpell(Item_HK[GetItemSlot(myHero, 3144)], target)
					end
				end
			
			
				if GetItemSlot(myHero, 3153) > 0 and ValidTarget(target, 550) then
					if myHero:GetSpellData(GetItemSlot(myHero, 3153)).currentCd == 0 then
						Control.CastSpell(Item_HK[GetItemSlot(myHero, 3153)], target)
					end
				end
			
			
				if GetItemSlot(myHero, 3146) > 0 and ValidTarget(target, 700) then
					if myHero:GetSpellData(GetItemSlot(myHero, 3146)).currentCd == 0 then
						Control.CastSpell(Item_HK[GetItemSlot(myHero, 3146)], target)
					end
				end
			
		
	end
end

function Rengar:Items2()
	
		if GetItemSlot(myHero, 3139) > 0 then
			if myHero:GetSpellData(GetItemSlot(myHero, 3139)).currentCd == 0 then
				if IsImmobile(myHero) then
					Control.CastSpell(Item_HK[GetItemSlot(myHero, 3139)], myHero)
				end
			end
		end
	
	
		if GetItemSlot(myHero, 3140) > 0 then
			if myHero:GetSpellData(GetItemSlot(myHero, 3140)).currentCd == 0 then
				if IsImmobile(myHero) then
					Control.CastSpell(Item_HK[GetItemSlot(myHero, 3140)], myHero)
				end
			end
		end
	
end


function Rengar:Draw()
	if myHero.dead then return end
	--PrintChat(myHero:GetSpellData(_Q).name)
	--PrintChat(myHero:GetSpellData(_W).name)
	--PrintChat(myHero:GetSpellData(_E).name)
	if target then
		--PrintChat("Target")
	end
	Draw.Circle(myHero.pos, RengarE.range, 1, Draw.Color(255, 0, 191, 255))
	for i, enemy in pairs(GetEnemyHeroes()) do
			if enemy:GetSpellData(SUMMONER_1).name == "SummonerSmite" or enemy:GetSpellData(SUMMONER_2).name == "SummonerSmite" then
				Smite = true
			else
				Smite = false
			end
			if Smite then
				if enemy.alive then
					if ValidTarget(enemy) then
						if GetDistance(myHero.pos, enemy.pos) > 3000 then
							Draw.Text("Jungler: Visible", 17, myHero.pos2D.x-45, myHero.pos2D.y+10, Draw.Color(0xFF32CD32))
						else
							Draw.Text("Jungler: Near", 17, myHero.pos2D.x-43, myHero.pos2D.y+10, Draw.Color(0xFFFF0000))
						end
					else
						Draw.Text("Jungler: Invisible", 17, myHero.pos2D.x-55, myHero.pos2D.y+10, Draw.Color(0xFFFFD700))
					end
				else
					Draw.Text("Jungler: Dead", 17, myHero.pos2D.x-45, myHero.pos2D.y+10, Draw.Color(0xFF32CD32))
				end
			end
	end
end



--[[function Rengar:UseE(target)
		local castpos,HitChance, pos = TPred:GetBestCastPosition(target, RengarE.delay, RengarE.width, RengarE.range, RengarE.speed, myHero.pos,RengarE.type)
		if (HitChance >= 1 ) then
			Control.CastSpell(HK_E, castpos)
		end	
end]]

function Rengar:UseE(target)
		local pred = _G.PremiumPrediction:GetPrediction(myHero, target, spellData)
		if pred.CastPos and _G.PremiumPrediction.HitChance.Medium(pred.HitChance) then
		    	Control.CastSpell(HK_E, pred.CastPos)
			if myHero.mana == 3 then
				EmpowerCast = true
				--PrintChat("E Before Empower")
			end 
		end 
end




function Rengar:Empowered()
	return myHero:GetSpellData().mana == 4
end


function Rengar:Combo()
	if target == nil then return end
	if Mode() == "Combo" and target then
			--PrintChat("Comboing")
			if IsReady(_E) and ValidTarget(target, 600) then
				if myHero:GetSpellData(_E).name == "RengarE" then
					self:UseE(target)
				elseif GetDistance(myHero.pos, target.pos) > 300 then
					--PrintChat("E Eing")
					self:UseE(target)
				end
			end
			--PrintChat("Qstuff")
			if IsReady(_Q) then
				--PrintChat("Combo Q Ready")
				if ValidTarget(target, 200) then
					--PrintChat("CastQ")
					if myHero:GetSpellData(_Q).name == "RengarQ" or not IsReady(_W) then
						Control.CastSpell(HK_Q)
					elseif myHero.health > myHero.maxHealth*0.2 then
						Control.CastSpell(HK_Q)
					end
				end
			end
		
			if IsReady(_W) and ValidTarget(target, 400) then
				if myHero:GetSpellData(_W).name == "RengarW" then
					Control.CastSpell(HK_W)
				elseif myHero.health < myHero.maxHealth*0.2 then
					Control.CastSpell(HK_W)
				end
			end

			if GetItemSlot(myHero, 3142) > 0 and ValidTarget(target, 1400) then
					if myHero:GetSpellData(GetItemSlot(myHero, 3142)).currentCd == 0 then
						Control.CastSpell(Item_HK[GetItemSlot(myHero, 3142)], myHero)
					end
				end


			
				if myHero:GetSpellData(SUMMONER_1).name == "S5_SummonerSmiteDuel" and IsReady(SUMMONER_1) and ValidTarget(target, 600) then
					Control.CastSpell(HK_SUMMONER_1, target)
				elseif myHero:GetSpellData(SUMMONER_2).name == "S5_SummonerSmiteDuel" and IsReady(SUMMONER_2) and ValidTarget(target, 600) then
					Control.CastSpell(HK_SUMMONER_2, target)
				end
			
	else		
		--PrintChat("NoNO")
	end
end

function Rengar:Harass()
	if target == nil then return end
	if Mode() == "Harass" then
		
			if IsReady(_Q) and myHero.attackData.state ~= STATE_WINDUP then
					if ValidTarget(target, 250) then
						Control.CastSpell(HK_Q)
					end
			end
			if IsReady(_W) and myHero.attackData.state ~= STATE_WINDUP then
					if ValidTarget(target, 400) then
						Control.CastSpell(HK_W)
					end
			end
			if IsReady(_E) and myHero.attackData.state ~= STATE_WINDUP then
					if ValidTarget(target, 1000) then
						self:UseE(target)
					end
			end
		
		
	end
end


function Rengar:JungleClear()
	for i = 1, Game.MinionCount() do
		local minion = Game.Minion(i)
    	if minion and minion.team == 300 or minion.team ~= myHero.team then
    		if IsReady(_Q) and minion then 
				if self.Menu.ClearMode.UseQ:Value() then
					if myHero.pos:DistanceTo(minion.pos) < 200 then
					Control.CastSpell(HK_Q)
					end
				end
			end
			if IsReady(_W) and minion and myHero.mana <= 3 then 
				if self.Menu.ClearMode.UseW:Value() then
					if myHero.pos:DistanceTo(minion.pos) < 300 then
					Control.CastSpell(HK_W)
					end
				end
			end
			if IsReady(_E) and minion and myHero.mana <= 3 then 
				if self.Menu.ClearMode.UseE:Value() then
					if myHero.pos:DistanceTo(minion.pos) < 600 then
					Control.CastSpell(HK_E,minion)
					end
				end
			end

			if GetItemSlot(myHero, 3074) > 0 and minion then
					if myHero:GetSpellData(GetItemSlot(myHero, 3074)).currentCd == 0 and myHero.pos:DistanceTo(minion.pos) < 300 then
						Control.CastSpell(Item_HK[GetItemSlot(myHero, 3074)], minion)
					end
				end

				if GetItemSlot(myHero, 3077) > 0 and minion then
					if myHero:GetSpellData(GetItemSlot(myHero, 3077)).currentCd == 0 and myHero.pos:DistanceTo(minion.pos) < 300 then
						Control.CastSpell(Item_HK[GetItemSlot(myHero, 3077)], minion)
					end
				end


		end
	end
end



function OnLoad()
	Rengar()
end