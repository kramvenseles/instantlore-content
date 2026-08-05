-- «Дух занят»: почти непрозрачная вуаль во весь экран с белым текстом по центру,
-- цвет которой раз в минуту перебирается фиолетовый → серый → чёрный.
--
-- Постоянный морок собран статичным HUD (три готовых слоя veil_*), а НЕ screen.fade:
-- у fade потолок 60с, он сам гаснет и не переживает перезаход. Цвет rect'а в HUD не
-- подставляется через ${...}, поэтому смена цвета = прятать текущий слой и показывать
-- следующий, а не менять значение у одного.
--
-- Включить троим:  /lore emit to Ник1 Ник2 Ник3 spirit.on
-- Снять:           /lore emit to Ник1 Ник2 Ник3 spirit.off

local VEILS = { "veil_purple", "veil_gray", "veil_black" }
local PERIOD = 60 -- секунд на цвет

local stop_cycle = nil
local current = nil

local function show(id)
    if current and current ~= id then
        lore.emit("hud.hide", { id = current })
    end
    lore.emit("hud.show", { id = id })
    current = id
end

lore.on("spirit.on", function()
    if stop_cycle then return end -- уже идёт — второй таймер не заводим

    local i = 1
    show(VEILS[i])

    stop_cycle = lore.every(PERIOD, function()
        i = (i % #VEILS) + 1
        show(VEILS[i])
    end)
end)

lore.on("spirit.off", function()
    if stop_cycle then
        stop_cycle()
        stop_cycle = nil
    end
    if current then
        lore.emit("hud.hide", { id = current })
        current = nil
    end
end)
