-- Демонстрация: скрипт живёт в контенте и обновляется без пересборки мода.
lore.log("демо 0.19: движок умеет действовать, а не только слушать")

lore.on("cutscene.play", function(data)
    lore.log("катсцена '" .. tostring(data.id) .. "', длительность " .. tostring(data.duration))
end)

lore.on("content.updated", function(data)
    lore.log("контент теперь версии " .. tostring(data.version))
end)

-- Проверка потолка на lore.report: 1000 докладов за один вызов. С rate-limit до сервера
-- дойдёт лишь всплеск (~20), остальное отбросится клиентом. Запуск: /lore emit <ник> demo.flood
lore.on("demo.flood", function()
    lore.log("флуд: шлю 1000 докладов")
    for i = 1, 1000 do
        lore.report("demo.spam", { n = i })
    end
    lore.log("флуд: цикл закончен")
end)

-- Проверка чтения мира: блок под ногами + сущности рядом. Запуск: /lore emit <ник> demo.scan
lore.on("demo.scan", function()
    local p = lore.player()
    if not p then return end

    local under = lore.block(p.x, p.y - 1, p.z)
    lore.log(string.format("под ногами: %s (solid=%s, air=%s)",
        under.id, tostring(under.solid), tostring(under.air)))

    local ents = lore.entities(16)
    lore.log("сущностей в 16 блоках: " .. #ents)
    for i, e in ipairs(ents) do
        lore.log(string.format("  %s на %.1f блока", e.type, e.distance))
        if i >= 5 then break end
    end
end)

-- Проверка всех четырёх эффекторов разом. Запуск: /lore emit <ник> demo.reactor {}
-- Сервер шлёт ОДНО событие, дальше клиент дирижирует сам: копит счётчик по таймеру,
-- шлёт значения в HUD через emit, по достижении 100 запускает эффект на позиции игрока
-- и отменяет собственный таймер. Ни одного пакета с сервера между кадрами.
lore.on("demo.reactor", function()
    lore.log("реактор: запуск")
    lore.emit("hud.show", { id = "reactor", values = { state = "ЗАПУСК", percent = 0, power = 0.0 } })

    local percent = 0
    local stop

    stop = lore.every(0.4, function()
        percent = percent + 5
        lore.emit("hud.set", { id = "reactor", values = { percent = percent, power = percent / 100.0 } })

        if percent >= 100 then
            lore.emit("hud.set", { id = "reactor", values = { state = "ОНЛАЙН" } })
            stop() -- повтор больше не нужен

            local p = lore.player()
            if p then
                lore.log(string.format("портал на %.1f %.1f %.1f", p.x, p.y, p.z))
                lore.emit("effect.play", { id = "portal", x = p.x, y = p.y, z = p.z })

                -- Канал вверх: докладываем серверу, что сцена доиграла. Сервер (Java)
                -- увидит это в LoreReportBus и может двинуть сценарий дальше.
                lore.report("demo.reactor_done", { percent = 100, x = p.x, y = p.y, z = p.z })
            end

            lore.after(5.0, function()
                lore.emit("hud.hide", { id = "reactor" })
                lore.log("реактор: HUD убран, сцена закончена")
            end)
        end
    end)
end)

-- P0: расширенные чтения (игрок/мир/инвентарь) + нарративные каналы.
-- Запуск: /lore emit <ник> demo.p0
lore.on("demo.p0", function()
    local p = lore.player()
    if not p then return end

    lore.log(string.format("игрок %s: hp %.1f/%.1f, еда %d, xp %d, режим %s",
        p.name, p.health, p.max_health, p.food, p.xp_level, tostring(p.gamemode)))
    lore.log(string.format("флаги: земля=%s вода=%s крадётся=%s бежит=%s измерение=%s",
        tostring(p.on_ground), tostring(p.in_water), tostring(p.sneaking),
        tostring(p.sprinting), tostring(p.dimension)))

    if p.held then
        lore.log("в руке: " .. p.held.name .. " x" .. p.held.count .. " (" .. p.held.id .. ")")
    else
        lore.log("руки пусты")
    end

    lore.log("эффектов активно: " .. #p.effects)
    for _, e in ipairs(p.effects) do
        lore.log(string.format("  %s ур.%d, %d тиков", e.id, e.amplifier, e.duration))
    end

    local w = lore.world()
    if w then
        lore.log(string.format("мир: время %d (день=%s), дождь=%s, гроза=%s, луна=%d",
            w.day_time, tostring(w.is_day), tostring(w.raining), tostring(w.thundering), w.moon_phase))
        lore.log(string.format("под игроком: биом %s, свет %d (блок %d / небо %d)",
            tostring(w.biome), w.light, w.block_light, w.sky_light))
    end

    local inv = lore.inventory()
    lore.log("занятых слотов инвентаря: " .. #inv)

    -- Нарративные каналы: заголовок с подстановкой имени + строка над хотбаром.
    lore.emit("title.show", {
        title = "§6Глава I",
        subtitle = "Пробуждение ${player}",
        values = { player = p.name },
        fade_in = 10, stay = 60, fade_out = 20,
    })
    lore.emit("actionbar.set", { text = "§7Испытание чтений пройдено" })
end)

-- P1: звук + toast + полоса босса. Запуск: /lore emit <ник> demo.p1
lore.on("demo.p1", function()
    lore.emit("sound.play", { id = "minecraft:block.bell.use", volume = 1.0, pitch = 1.2 })
    lore.emit("toast.show", { title = "§eОткрытие", description = "Канал toast работает" })
    lore.emit("bossbar.show", {
        id = "reactor", title = "§cЯдро реактора",
        percent = 0.0, color = "red", style = "notched_10",
    })

    local pct = 0.0
    local stop
    stop = lore.every(0.3, function()
        pct = pct + 0.1
        lore.emit("bossbar.set", { id = "reactor", percent = pct })
        if pct >= 1.0 then
            stop()
            lore.emit("bossbar.set", { id = "reactor", title = "§aЯдро стабильно" })
            lore.after(3.0, function()
                lore.emit("bossbar.hide", { id = "reactor" })
                lore.log("P1: полоса убрана")
            end)
        end
    end)
end)

-- P1: смена музыкального фона. Запуск: /lore emit <ник> demo.music
lore.on("demo.music", function()
    lore.emit("music.play", { id = "minecraft:music_disc.cat" })
    lore.log("P1: музыка запущена, стоп через 6с")
    lore.after(6.0, function()
        lore.emit("music.stop", {})
        lore.log("P1: музыка остановлена")
    end)
end)

-- P2.7 (рамка-подсветка в мире) + P2.8 (локальная память). Запуск: /lore emit <ник> demo.world
lore.on("demo.world", function()
    local p = lore.player()
    if not p then return end

    -- P2.8: счётчик заходов переживает реконнект и перезагрузку контента
    local visits = (lore.load("visits") or 0) + 1
    lore.save("visits", visits)
    lore.log("заход №" .. visits .. " (память на диске, переживает реконнект)")

    -- P2.7: рамка-подсветка на блоке под ногами, видна только этому игроку
    lore.emit("marker.set", { id = "here", type = "box",
        x = math.floor(p.x) + 0.5, y = math.floor(p.y) - 1, z = math.floor(p.z) + 0.5,
        size = 1, color = "#FF00E5FF" })

    lore.after(12.0, function()
        lore.emit("marker.remove", { id = "here" })
        lore.log("маркер снят")
    end)
end)

-- ─────────────────────────────────────────────────────────
-- item.use — предмет пула применён. Событие шлёт СЕРВЕР, увидев ванильный пакет
-- использования, поэтому это авторитетный сигнал, а не доклад с машины игрока.
-- Проверка: /lore give <ник> 0  → ПКМ свитком
-- ─────────────────────────────────────────────────────────
lore.on("item.use", function(data)
    lore.log("применён предмет: слот " .. tostring(data.slot) .. " (" .. tostring(data.name) .. ")")

    if data.name == "scroll" then
        lore.emit("title.show", {
            title = "Свиток раскрыт",
            subtitle = "Слова гаснут, едва прочитанные",
            fade_in = 5, stay = 40, fade_out = 10
        })
        lore.emit("sound.play", { id = "minecraft:block.enchantment_table.use" })

        local p = lore.player()
        if p then
            -- Персональный маркер-текст: виден только тому, кто прочёл свиток.
            lore.emit("marker.set", {
                id = "scroll_echo", type = "text",
                x = p.x, y = p.y + 2.2, z = p.z,
                size = 1.5, color = "#FFD9A8", text = "здесь был знак"
            })
            -- И луч от свитка вверх — проверка типа line.
            lore.emit("marker.set", {
                id = "scroll_beam", type = "line",
                x = p.x, y = p.y, z = p.z,
                x2 = p.x, y2 = p.y + 2.0, z2 = p.z,
                size = 1.0, color = "#FFD9A8"
            })
            lore.after(8, function()
                lore.emit("marker.remove", { id = "scroll_echo" })
                lore.emit("marker.remove", { id = "scroll_beam" })
            end)
        end
    end
end)
