-- Наблюдатель здоровья: ловит момент урона, а не его последствия.
--
-- ⚠️ Зачем вообще. Урон нельзя мерить опросом здоровья после события: оно отрастает,
-- и опрос измерит регенерацию. На отладке походки это дважды дало отчёт «урона нет»
-- о дороге, где игрок терял сердце. Накопительный счётчик статистики честен, но
-- отвечает только «сколько», и молчит о том, где и обо что.
--
-- Здесь урон ловится в момент, когда он случился: клиент видит своё здоровье каждый
-- кадр, и просадка между двумя опросами — это и есть удар, даже если через секунду
-- всё отросло обратно.
--
-- Живёт в контенте, а не в моде: обновляется выкаткой на CDN.

local HURT_EPSILON = 0.01 -- меньше этого — шум округления, а не урон

-- ⚠️ СЕКУНДЫ, не миллисекунды. Первая версия просила «50», имея в виду тик, и получила
-- опрос раз в 50 секунд. Наблюдатель при этом выглядел работающим: он отвечал на
-- hp.state, вёл пик высоты, а урон замечал — через три минуты после удара, слив в один
-- отсчёт и падение, и регенерацию. Дорога длиной три секунды пролетала между опросами
-- целиком, и отчёт выходил «урона не было».
local TICK_SECONDS = 0.05

-- Сколько опросов помнить последнее падение: урон приходит на тике приземления
-- или следующем, и к этому моменту пик высоты уже сброшен.
local FALL_MEMORY_TICKS = 20

local last_health = nil
local peak_y = nil        -- высшая точка с последнего касания земли
local was_on_ground = true
local last_fall = 0.0     -- высота последнего приземления, запомненная в его момент
local fall_fresh = 0      -- сколько опросов эта память ещё считается свежей

lore.every(TICK_SECONDS, function()
    local p = lore.player()
    if not p then return end

    -- ⚠️ Высоту падения надо ЗАПОМНИТЬ в момент приземления, а не спрашивать после.
    --
    -- Первая версия обнуляла пик раньше, чем читала его: на тике приземления
    -- on_ground уже истина, пик сбрасывался на текущую высоту, и падение выходило
    -- нулевым — ровно в том единственном кадре, ради которого всё и писалось.
    -- Урон же приходит на том же тике или следующем, поэтому запомненное держим
    -- ещё секунду.
    local landed = p.on_ground and not was_on_ground

    if landed then
        last_fall = (peak_y ~= nil and peak_y > p.y) and (peak_y - p.y) or 0.0
        fall_fresh = FALL_MEMORY_TICKS
    elseif fall_fresh > 0 then
        fall_fresh = fall_fresh - 1
    end

    if p.on_ground then
        peak_y = p.y
    elseif peak_y == nil or p.y > peak_y then
        peak_y = p.y
    end

    was_on_ground = p.on_ground

    if last_health == nil then
        last_health = p.health
        return
    end

    local lost = last_health - p.health
    last_health = p.health

    if lost <= HURT_EPSILON then
        return
    end

    -- Причину клиент точно не знает, поэтому не выдумываем её, а сообщаем признаки:
    -- падал ли, с какой высоты, был ли это кадр приземления. Разбираться — серверу.
    local fell = 0.0
    if fall_fresh > 0 then
        fell = last_fall              -- только что приземлились: высота запомнена
    elseif peak_y ~= nil and peak_y > p.y then
        fell = peak_y - p.y           -- ещё в воздухе: считаем по текущему пику
    end

    lore.report("player.hurt", {
        lost = lost,
        health = p.health,
        max_health = p.max_health,
        landed = landed,
        fell = fell,
        in_water = p.in_water,
        in_lava = p.in_lava,
        x = p.x, y = p.y, z = p.z,
    })

    lore.log(string.format(
        "урон %.1f (осталось %.1f), падение %.2f блока, приземление=%s",
        lost, p.health, fell, tostring(landed)))
end)

-- Ручная проверка самого наблюдателя: /lore emit <ник> hp.state
-- ⚠️ Без неё «докладов нет» неотличимо от «наблюдатель не запустился».
lore.on("hp.state", function()
    local p = lore.player()
    if not p then
        lore.log("наблюдатель здоровья: игрока нет")
        return
    end

    lore.log(string.format(
        "наблюдатель здоровья жив: %.1f/%.1f, на земле=%s, пик высоты=%s",
        p.health, p.max_health, tostring(p.on_ground), tostring(peak_y)))
end)

lore.log("наблюдатель здоровья запущен")
