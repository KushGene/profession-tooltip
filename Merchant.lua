-- Merchant.lua
-- Compares the prices of an open vendor with the base prices in the data (recipe items, reagents)
-- and records what the character paid at its reputation (Sources.lua: ns.ObserveDiscount). That is
-- how Tools/build_sources.py learns the reputation discount of every standing.
local _, ns = ...

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

-- NPC ID of a unit ("Creature-0-…-<npcID>-<spawn>"), or nil
function ns.GetUnitNPCID(unit)
    local guid = UnitGUID and UnitGUID(unit)
    if type(guid) ~= "string" or IsSecret(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" then return tonumber(id) end
end

local function ItemID(index)
    local id = GetMerchantItemID and GetMerchantItemID(index)
    if type(id) == "number" and not IsSecret(id) then return id end
    local link = GetMerchantItemLink and GetMerchantItemLink(index)
    if type(link) == "string" and not IsSecret(link) then
        return tonumber(link:match("item:(%d+)"))
    end
end

-- Price of the slot (for its stack) and the stack size
local function PriceInfo(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then return info.price, info.stackCount end
    end
    if GetMerchantItemInfo then
        local _, _, price, quantity = GetMerchantItemInfo(index)
        return price, quantity
    end
end

local function Scan()
    if not (GetMerchantNumItems and ns.ObserveDiscount) then return end
    local npcID = ns.GetUnitNPCID("npc")
    if not (npcID and ns.GetNPCFaction(npcID)) then return end
    for index = 1, GetMerchantNumItems() do
        local itemID = ItemID(index)
        local price, quantity = PriceInfo(index)
        if itemID and type(price) == "number" and not IsSecret(price) and price > 0 then
            local base, isUnit = ns.GetVendorBasePrice(npcID, itemID)
            if base then
                if isUnit then
                    quantity = (type(quantity) == "number" and not IsSecret(quantity) and quantity > 0) and quantity or 1
                    base = base * quantity
                end
                ns.ObserveDiscount("v", npcID, itemID, base, price)
            end
        end
    end
end

-- Slightly delayed: the list fills in after MERCHANT_SHOW
ns.RegisterEvent("MERCHANT_SHOW", function()
    C_Timer.After(0.3, function() pcall(Scan) end)
end)
