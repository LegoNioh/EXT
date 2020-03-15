
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
require "PussyDamageLib"
--require('PussyDamageLib')

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
		--PrintChat("SDK")
		return _G.SDK.TargetSelector:GetTarget(range, _G.SDK.DAMAGE_TYPE_PHYSICAL);
	else
		--return _G.SDK.TargetSelector:GetTarget(range, _G.SDK.DAMAGE_TYPE_PHYSICAL)
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

local castSpell = {state = 0, tick = GetTickCount(), casting = GetTickCount() - 1000, mouse = mousePos}
local attackState = 1
local attackStateAdd = 0
local MainHand = "None"
local OffHand = "None"
local FlameQR = Game:Timer()
local SniperQR = Game:Timer()
local SlowQR = Game:Timer()
local BounceQR = Game:Timer()
local HealQR = Game:Timer()
local Wtick = GetTickCount()
local MainAtTime = MainHand
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
	RengarQ = {range = 400, width = 100, speed = 3000, delay = 0.25, collision = false, aoe = true, type = "Targetted"}
	RengarW = {range = 400}
	RengarE = {range = 325, width = 100, speed = 2500, delay = 0.25, collision = false, aoe = false, type = "line"}
	RengarE = {range = 325, width = 100, speed = 2500, delay = 0.25, collision = false, aoe = false, type = "line"}
	self.e = {Type = _G.SPELLTYPE_LINE, Range = 1000, Radius = 40, Speed = 1500, Collision = true, MaxCollision = 1, CollisionTypes = {0, 2, 3}}
	QSniperSpell = {speed = 1850, range = 1450, delay = 0.25, radius = 60, collision = {"minion"}, type = "linear"}
	QFlameSpell = {speed = 1850, range = 850, delay = 0.25, radius = 100, collision = {}, type = "linear"}
	WspellData = {speed = 1500, range = 260, delay = 0.25, radius = 260, collision = {}, type = "linear"}
	EspellData = {speed = 2500, range = 325, delay = 0.25, radius = 100, collision = {}, type = "linear"}
	RspellData = {speed = 1000, range = 1300, delay = 0.25, radius = 110, collision = {}, type = "linear"}
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
	target = GetTarget(3000)
	OffHand = self:GetOffHand()
	--Draw.Text(myHero:GetSpellData(_W).currentCd, 17, myHero.pos2D.x-85, myHero.pos2D.y-100, Draw.Color(0xFF32CD32))
	MainHand = self:GetGun()
	--self:KS()
	--RivenFengShuiEngine	
	Item_HK[ITEM_1] = HK_ITEM_1
	Item_HK[ITEM_2] = HK_ITEM_2
	Item_HK[ITEM_3] = HK_ITEM_3
	Item_HK[ITEM_4] = HK_ITEM_4
	Item_HK[ITEM_5] = HK_ITEM_5
	Item_HK[ITEM_6] = HK_ITEM_6
	Item_HK[ITEM_7] = HK_ITEM_7
	self:Combo()
	attackState = myHero.attackData.state
	if attackState == 3 then
		attackStateAdd = attackStateAdd + attackState
	end
	if self.Menu.ClearMode.clearActive:Value() then
		self:JungleClear()
	end
end

function string.starts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
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
	Draw.Circle(myHero.pos, 225, 1, Draw.Color(255, 0, 191, 255))
	local Qname = myHero:GetSpellData(14).name
	local Qname1 = myHero:GetSpellData(_R).range
	local Qname2 = myHero:GetSpellData(_R).speed
	local Qname3 = myHero:GetSpellData(_R).width
	--local Qname4 = myHero:GetSpellData(_R).ammoCurrentCd
	--Draw.Text(Qname, 17, myHero.pos2D.x-45, myHero.pos2D.y+10, Draw.Color(0xFF32CD32))
	--Draw.Text(Qname1, 17, myHero.pos2D.x-45, myHero.pos2D.y+30, Draw.Color(0xFF32CD32))
	--Draw.Text(Qname2, 17, myHero.pos2D.x-45, myHero.pos2D.y+50, Draw.Color(0xFF32CD32))
	--Draw.Text(Qname3, 17, myHero.pos2D.x-45, myHero.pos2D.y+70, Draw.Color(0xFF32CD32))
	--Draw.Text(Qname4, 17, myHero.pos2D.x-45, myHero.pos2D.y+90, Draw.Color(0xFF32CD32))

	--local Ename = myHero:GetSpellData(_E).ammo
	--Draw.Text(Ename, 17, myHero.pos2D.x-45, myHero.pos2D.y+110, Draw.Color(0xFF32CD32))

	Draw.Text(MainHand, 25, 770, 950, Draw.Color(0xFF32CD32))
	Draw.Text(OffHand, 25, 870, 950, Draw.Color(0xFF0000FF))
	--Draw.Text(myHero:GetSpellData(0).currentCd, 25, 870, 850, Draw.Color(0xFF0000FF))
	--[[for i = 0, myHero.buffCount do
		local buff = myHero:GetBuff(i)
		if buff.name == "ApheliosOffHandBuffCalibrum" then
			Draw.Text(buff.count, 15, 500, 650, Draw.Color(0xFF32CD32))
		end
		if buff.name == "ApheliosOffHandBuffGravitum" then
			Draw.Text(buff.count, 15, 500, 650, Draw.Color(0xFF32CD32))
		end
		if buff.name == "ApheliosOffHandBuffSeverum" then
			Draw.Text(buff.count, 15, 500, 650, Draw.Color(0xFF32CD32))
		end
		if buff.name == "ApheliosOffHandBuffCrescendum" then
			Draw.Text(buff.count, 15, 500, 650, Draw.Color(0xFF32CD32))
		end
		if buff.name == "ApheliosOffHandBuffInfernum" then
			Draw.Text(buff.count, 15, 500, 650, Draw.Color(0xFF32CD32))
		end
		Draw.Text(buff.name, 15, 1170, 650-(i*20), Draw.Color(0xFF32CD32))
	end]]--

	return 0

end

function SetMovement(bool)
	if _G.SDK then
		_G.SDK.Orbwalker:SetMovement(bool)
		_G.SDK.Orbwalker:SetAttack(bool)
	end
	if bool then
		castSpell.state = 0
	end
end

function EnableMovement()
	SetMovement(true)
end

function ReturnCursor(pos)
	Control.SetCursorPos(pos)
	DelayAction(EnableMovement,0.1)
end

function LeftClick(pos)
	Control.mouse_event(MOUSEEVENTF_LEFTDOWN)
	Control.mouse_event(MOUSEEVENTF_LEFTUP)
	DelayAction(ReturnCursor,0.05,{pos})
end

function Rengar:CastSpell(spell,pos)
	local delay = 20
	local ticker = GetTickCount()
	if castSpell.state == 0 and ticker > castSpell.casting then
		castSpell.state = 1
		castSpell.mouse = mousePos
		castSpell.tick = ticker
		if ticker - castSpell.tick < Game.Latency() then
			SetMovement(false)
			Control.SetCursorPos(pos)
			Control.KeyDown(spell)
			Control.KeyUp(spell)
			DelayAction(LeftClick,delay/1000,{castSpell.mouse})
			castSpell.casting = ticker + 500
		end
	end
end

function castw()
	Control.CastSpell(HK_W)
end

function Rengar:KS()
	if target and IsReady(_R) and ValidTarget(target, 700) then
		local RDmg = getdmg("R", target, myHero, myHero:GetSpellData(_R).level)
		--PrintChat(RDmg - target.health)
		if target.health < RDmg then
			if myHero:GetSpellData(_R).name == "RivenFengShuiEngine" then
				Control.CastSpell(HK_R)
			else
				self:UseR(target)
			end
		end
	end
end

function Rengar:GetOffHand()
	for i = 0, myHero.buffCount do
		local buff = myHero:GetBuff(i)
		if buff.name == "ApheliosOffHandBuffCalibrum" then
			return "Sniper" 
		end
		if buff.name == "ApheliosOffHandBuffGravitum" then
			return "Slow" 
		end
		if buff.name == "ApheliosOffHandBuffSeverum" then
			return "Heal" 
		end
		if buff.name == "ApheliosOffHandBuffCrescendum" then
			return "Bounce" 
		end
		if buff.name == "ApheliosOffHandBuffInfernum" then
			return "Flame" 
		end
	end
end

function Rengar:GetGun()
	if myHero:GetSpellData(_Q).name == "ApheliosCalibrumQ" then
		return "Sniper" 
	end
	if myHero:GetSpellData(_Q).name == "ApheliosGravitumQ" then
		return "Slow" 
	end
	if myHero:GetSpellData(_Q).name == "ApheliosSeverumQ" then
		return "Heal" 
	end
	if myHero:GetSpellData(_Q).name == "ApheliosCrescendumQ" then
		return "Bounce" 
	end
	if myHero:GetSpellData(_Q).name == "ApheliosInfernumQ" then
		return "Flame" 
	end
end

function Rengar:UseQSniper(target)
		local pred = _G.PremiumPrediction:GetPrediction(myHero, target, QSniperSpell)
		if pred.CastPos and _G.PremiumPrediction.HitChance.Medium(pred.HitChance) then
		    	Control.CastSpell(HK_Q, pred.CastPos)
		    	--DelayAction(RightClick,1.5,{target, mousePos})
		end 
end

function Rengar:UseRAll(target)
		local pred = _G.PremiumPrediction:GetPrediction(myHero, target, RspellData)
		if pred.CastPos and _G.PremiumPrediction.HitChance.Medium(pred.HitChance) then
		    	if myHero.pos:DistanceTo(pred.CastPos) <= 850 and target.health < target.maxHealth/2 then
		    		Control.CastSpell(HK_R, pred.CastPos)
		    	end
		end 
end

function Rengar:UseQFlame(target)
		local pred = _G.PremiumPrediction:GetPrediction(myHero, target, QFlameSpell)
		if pred.CastPos and _G.PremiumPrediction.HitChance.Medium(pred.HitChance) then
		    	Control.CastSpell(HK_Q, pred.CastPos)
		end 
end

function SniperQOffCd()

end

function RightClick(pos)
	Control.mouse_event(MOUSEEVENTF_LEFTDOWN)
	Control.mouse_event(MOUSEEVENTF_LEFTUP)
	DelayAction(ReturnCursor,0.05,{pos})
end

function RightClickQ(start, pos)
	SetMovement(false)
	Control.SetCursorPos(start)
	DelayAction(RightClick,0.2,{pos})
end


function Rengar:Combo()
	if target == nil then return end
	if Mode() == "Combo" and target then
			self:Items1()
			self:Items2()
			--PrintChat("wtf")
--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ SNIPER SNIPER SNIPER SNIPER @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
			if MainHand == "Sniper" then
				if not IsReady(_Q) then
					SniperQR = Game:Timer() + myHero:GetSpellData(0).currentCd
				end
				if OffHand == "Slow" then
					if IsReady(_Q) and ValidTarget(target, 1450) then
						self:UseQSniper(target)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if not IsReady(_Q) and myHero.pos:DistanceTo(target.pos) <= 500 then
							Control.CastSpell(HK_W)
						end
						if SlowQR < Game:Timer() then
							--Control.CastSpell(HK_W)
						end 
					end
					if IsReady(_R) then

					end
					-- if target has Q buff, switch to W
				end
				if OffHand == "Flame" then
					if IsReady(_Q) and ValidTarget(target, 1450) then
						self:UseQSniper(target)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						--PrintChat("W REady")
						if myHero.pos:DistanceTo(target.pos) <= 500 then
							Control.CastSpell(HK_W)
						end 
						if FlameQR < Game:Timer() and myHero.pos:DistanceTo(target.pos) <= 650 then
							Control.CastSpell(HK_W)
						end 
					end
					if IsReady(_R) then

					end
				end
				if OffHand == "Bounce" then
					if IsReady(_Q) and ValidTarget(target, 1450) then
						self:UseQSniper(target)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if myHero.pos:DistanceTo(target.pos) < 350 then
							Control.CastSpell(HK_W)
						end
						if BounceQR < Game:Timer() and myHero.pos:DistanceTo(target.pos) <= 475 then
							Control.CastSpell(HK_W)
						end  
					end
					if IsReady(_R) then

					end
				end
				if OffHand == "Heal" then
					if IsReady(_Q) and ValidTarget(target, 1450) then
						self:UseQSniper(target)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if myHero.pos:DistanceTo(target.pos) <= 300 or myHero.health < myHero.maxHealth*0.3 then
							Control.CastSpell(HK_W)
						end
						if HealQR < Game:Timer() and myHero.pos:DistanceTo(target.pos) <= 550 then
							Control.CastSpell(HK_W)
						end  
					end
					if IsReady(_R) then
						self:UseRAll(target)
					end
				end
			end

--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ SLOW SLOW SLOW SLOW @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


			if MainHand == "Slow" then
				if not IsReady(_Q) then
					SlowQR = Game:Timer() + myHero:GetSpellData(0).currentCd
				end
				if OffHand == "Sniper" then
					if IsReady(_Q) then
						Control.CastSpell(HK_Q)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if myHero.pos:DistanceTo(target.pos) > 550 then
							Control.CastSpell(HK_W)
						end 
					end
					if IsReady(_R) then
						self:UseRAll(target)
					end
				end
				if OffHand == "Flame" then
					if IsReady(_Q) then
						Control.CastSpell(HK_Q)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if FlameQR < Game:Timer() and myHero.pos:DistanceTo(target.pos) <= 650 then
							Control.CastSpell(HK_W)
						end  
					end
					if IsReady(_R) then

					end
				end
				if OffHand == "Bounce" then
					if IsReady(_Q) then
						Control.CastSpell(HK_Q)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if not IsReady(_Q) and myHero.pos:DistanceTo(target.pos) < 350 then
							Control.CastSpell(HK_W)
						end 
					end
					if IsReady(_R) then

					end
				end
				if OffHand == "Heal" then
					if IsReady(_Q) then
						Control.CastSpell(HK_Q)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if not IsReady(_Q) and myHero.health < myHero.maxHealth/2 then
							Control.CastSpell(HK_W)
						end
						if HealQR < Game:Timer() and myHero.pos:DistanceTo(target.pos) <= 650 then
							Control.CastSpell(HK_W)
						end 
					end
					if IsReady(_R) then
						self:UseRAll(target)
					end
				end
			end


--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ FLAME FLAME FLAME FLAME @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


			if MainHand == "Flame" then
				if not IsReady(_Q) then
					FlameQR = Game:Timer() + myHero:GetSpellData(0).currentCd
				end
				if OffHand == "Slow" then
					if IsReady(_Q) and ValidTarget(target, 850) then
						self:UseQFlame(target)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if not IsReady(_Q) then
							Control.CastSpell(HK_W)
						end
					end
					if IsReady(_R) then
						self:UseRAll(target)
					end
				end
				if OffHand == "Sniper" then
					if IsReady(_Q) and ValidTarget(target, 850) then
						self:UseQFlame(target)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if myHero.pos:DistanceTo(target.pos) > 550 then
							Control.CastSpell(HK_W)
						end 
					end
					if IsReady(_R) then
						self:UseRAll(target)
					end
				end
				if OffHand == "Bounce" then
					if IsReady(_Q) and ValidTarget(target, 850) then
						self:UseQFlame(target)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if not IsReady(_Q) and myHero.pos:DistanceTo(target.pos) < 550 then
							Control.CastSpell(HK_W)
						end 
					end
					if IsReady(_R) then
						self:UseRAll(target)
					end
				end
				if OffHand == "Heal" then
					if IsReady(_Q) and ValidTarget(target, 850) then
						self:UseQFlame(target)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if HealQR < Game:Timer() and myHero.pos:DistanceTo(target.pos) <= 650 then
							Control.CastSpell(HK_W)
						end  
					end
					if IsReady(_R) then
						self:UseRAll(target)
					end
				end
			end


--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ BOUNCE BOUNCE BOUNCE BOUNCE @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


			if MainHand == "Bounce" then
				if not IsReady(_Q) then
					BounceQR = Game:Timer() + myHero:GetSpellData(0).currentCd
				end
				if OffHand == "Slow" then
					if IsReady(_Q) and ValidTarget(target, 475) then
						Control.CastSpell(HK_Q, target)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if IsReady(_Q) then
							if myHero.pos:DistanceTo(target.pos) > 475 then
								Control.CastSpell(HK_W)
							end
						else
							if myHero.pos:DistanceTo(target.pos) > 400 then
								Control.CastSpell(HK_W)
							end
						end 
					end
					if IsReady(_R) then
						self:UseRAll(target)
					end
				end
				if OffHand == "Flame" then
					if IsReady(_Q) and ValidTarget(target, 475) then
						Control.CastSpell(HK_Q, target)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if FlameQR < Game:Timer() and myHero.pos:DistanceTo(target.pos) <= 650 then
							Control.CastSpell(HK_W)
						end  
					end
					if IsReady(_R) then

					end
				end
				if OffHand == "Sniper" then
					if IsReady(_Q) and ValidTarget(target, 475) then
						Control.CastSpell(HK_Q, target)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if IsReady(_Q) then
							if myHero.pos:DistanceTo(target.pos) > 475 then
								Control.CastSpell(HK_W)
							end
						else
							if myHero.pos:DistanceTo(target.pos) > 350 then
								Control.CastSpell(HK_W)
							end
						end 
					end
					if IsReady(_R) then
						self:UseRAll(target)
					end
				end
				if OffHand == "Heal" then
					--if IsReady(_Q) and ValidTarget(target, 475) then
						--Control.CastSpell(HK_Q, target)
					--end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if HealQR < Game:Timer() and myHero.pos:DistanceTo(target.pos) <= 650 then
							Control.CastSpell(HK_W)
						end  
					end
					if IsReady(_R) then
						self:UseRAll(target)
					end
				end
			end


--@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ HEAL HEAL HEAL HEAL @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@


			if MainHand == "Heal" then	
				--PrintChat("Heal")
				if not IsReady(_Q) then
					HealQR = Game:Timer() + myHero:GetSpellData(0).currentCd
				end
				if OffHand == "Slow" then
					if IsReady(_Q) and ValidTarget(target, 620) then
						Control.CastSpell(HK_Q)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if not IsReady(_Q) and myHero.health > myHero.maxHealth*0.7 then
							Control.CastSpell(HK_W)
						end
					end
					if IsReady(_R) then

					end
				end
				if OffHand == "Flame" then
					if IsReady(_Q) and ValidTarget(target, 620) then
						Control.CastSpell(HK_Q)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if not IsReady(_Q) and myHero.pos:DistanceTo(target.pos) < 550 and myHero.health > myHero.maxHealth*0.2 then
							Control.CastSpell(HK_W)
						end 
					end
					if IsReady(_R) then

					end
				end
				if OffHand == "Bounce" then
					if IsReady(_Q) and ValidTarget(target, 620) then
						Control.CastSpell(HK_Q)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if not IsReady(_Q) and myHero.pos:DistanceTo(target.pos) < 550 and myHero.health > myHero.maxHealth*0.2 then
							Control.CastSpell(HK_W)
						end 
					end
					if IsReady(_R) then

					end
				end
				if OffHand == "Sniper" then
					if IsReady(_Q) and ValidTarget(target, 620) then
						Control.CastSpell(HK_Q)
					end
					if IsReady(_E) then

					end
					if IsReady(_W) then
						if myHero.pos:DistanceTo(target.pos) > 350 and myHero.health > myHero.maxHealth*0.3 then
							Control.CastSpell(HK_W)
						end 
					end
					if IsReady(_R) then

					end
				end
			end


			if myHero:GetSpellData(SUMMONER_1).name == "S5_SummonerSmiteDuel" and IsReady(SUMMONER_1) and ValidTarget(target, 600) then
				Control.CastSpell(HK_SUMMONER_1, target)
			elseif myHero:GetSpellData(SUMMONER_2).name == "S5_SummonerSmiteDuel" and IsReady(SUMMONER_2) and ValidTarget(target, 600) then
				Control.CastSpell(HK_SUMMONER_2, target)
			end
	end
end

function Rengar:UseR(target)
		local pred = _G.PremiumPrediction:GetPrediction(myHero, target, RspellData)
		if pred.CastPos and _G.PremiumPrediction.HitChance.Medium(pred.HitChance) then
		    	Control.CastSpell(HK_R, pred.CastPos)
		end 
end



function Rengar:Harass()
	if target == nil then return end
	if Mode() == "Harass" then
			
	end
end


function Rengar:JungleClear()
end



function OnLoad()
	Rengar()
end