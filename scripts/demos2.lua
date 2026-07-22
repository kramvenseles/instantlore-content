-- ─────────────────────────────────────────────────────────
-- demo.quest  — мини-квест: диалог → bossbar-трекер → финал
-- Запуск: /lore emit <ник> demo.quest
-- ─────────────────────────────────────────────────────────
lore.on("demo.quest", function()
    local p = lore.player()
    if not p then return end

    -- 1. Диалог от имени Хранителя. Ответ придёт докладом dialog.choice.
    lore.emit("dialog.show", {
        id    = "guardian",
        values = { player = p.name },
    })
end)

-- Реакция на выбор игрока в диалоге Хранителя.
lore.on("dialog.choice", function(data)
    if data.id ~= "guardian" then return end
    local key = tostring(data.key)

    if key == "leave" then
        lore.emit("actionbar.set", { text = "§7Хранитель провожает тебя взглядом." })
        lore.emit("sound.play", { id = "minecraft:entity.enderman.stare", volume = 0.8, pitch = 0.6 })
        return
    end

    if key == "boast" then
        lore.emit("sound.play", { id = "minecraft:entity.lightning_bolt.thunder", volume = 0.6, pitch = 1.5 })
        lore.emit("title.show", {
            title    = "§c⚔ Хранитель разгневан",
            subtitle = "§7Ты получишь по заслугам, смертный.",
            fade_in = 10, stay = 40, fade_out = 15,
        })
        return
    end

    -- key == "greet" → принять квест
    lore.emit("sound.play", { id = "minecraft:entity.villager.ambient", volume = 1.0, pitch = 0.9 })
    lore.emit("title.show", {
        title    = "§aКвест принят",
        subtitle = "§7Найди Алтарь Забытых",
        fade_in = 8, stay = 50, fade_out = 15,
    })

    -- bossbar-трекер квеста
    lore.emit("bossbar.show", {
        id      = "quest",
        title   = "§eАлтарь Забытых — 0 / 1",
        percent = 0.0,
        color   = "yellow",
        style   = "progress",
    })

    -- Через 15 секунд засчитываем «нашёл» (в реальности сервер делал бы это по серверной
    -- проверке позиции, но тут симулируем ход времени для демо)
    lore.after(15.0, function()
        lore.emit("bossbar.set",  { id = "quest", title = "§aАлтарь Забытых — найден!", percent = 1.0, color = "green" })
        lore.emit("sound.play",   { id = "minecraft:ui.toast.challenge_complete", volume = 1.0, pitch = 1.0 })
        lore.emit("toast.show",   { title = "§6Квест выполнен", description = "Алтарь Забытых найден" })
        lore.emit("title.show",   { title = "§6✔ Квест выполнен", subtitle = "§7Хранитель доволен",
                                     fade_in = 10, stay = 60, fade_out = 20 })
        lore.emit("actionbar.set", { text = "§aНаграда получена" })

        lore.after(5.0, function()
            lore.emit("bossbar.hide", { id = "quest" })
        end)
    end)
end)


-- ─────────────────────────────────────────────────────────
-- demo.story — атмосферная сцена + память
-- Запуск: /lore emit <ник> demo.story
-- ─────────────────────────────────────────────────────────
lore.on("demo.story", function()
    local p = lore.player()
    if not p then return end

    -- Считаем, сколько раз игрок смотрел эту сцену
    local seen = (lore.load("story_seen") or 0) + 1
    lore.save("story_seen", seen)

    local suffix = seen == 1 and "§7(первый просмотр)" or ("§8(просмотр №" .. seen .. ")")

    -- Рамка на блоке под игроком
    lore.emit("marker.set", {
        id    = "story_here",
        type  = "box",
        x     = math.floor(p.x) + 0.5,
        y     = math.floor(p.y) - 1,
        z     = math.floor(p.z) + 0.5,
        size  = 1,
        color = "#FFAA00FFFF",
    })

    -- Музыкальный фон
    lore.emit("music.play", { id = "minecraft:music.creative", replace = true })

    -- Катсцена с таймлайном событий
    lore.emit("cutscene.play", { id = "intro" })

    -- После катсцены (8 секунд) — финальный аккорд
    lore.after(8.5, function()
        lore.emit("music.stop", {})
        lore.emit("toast.show",  { title = "§bГлава I", description = "Пробуждение " .. suffix })
        lore.emit("sound.play",  { id = "minecraft:ui.toast.challenge_complete", volume = 0.7, pitch = 0.8 })
        lore.emit("actionbar.set", { text = suffix })
        lore.emit("marker.remove", { id = "story_here" })
        lore.report("demo.story_done", { seen = seen })
    end)
end)


-- ─────────────────────────────────────────────────────────
-- demo.env — реагирует на окружение (время, здоровье, биом)
-- Запуск: /lore emit <ник> demo.env
-- ─────────────────────────────────────────────────────────
lore.on("demo.env", function()
    local p = lore.player()
    local w = lore.world()
    if not p or not w then return end

    -- Время суток → атмосферная подпись
    local time_text
    if w.is_day then
        time_text = "§eSолнце над древними руинами"
    else
        time_text = "§9Тени ползут из забытых мест"
    end

    -- Здоровье → предупреждение
    local hp_fraction = p.health / p.max_health
    local hp_color
    if hp_fraction > 0.6 then
        hp_color = "§a"
    elseif hp_fraction > 0.3 then
        hp_color = "§e"
    else
        hp_color = "§c"
    end
    local hp_text = hp_color .. string.format("HP: %.0f / %.0f", p.health, p.max_health)

    -- Биом
    local biome_short = (w.biome or ""):gsub("minecraft:", "")

    -- bossbar с состоянием окружения
    lore.emit("bossbar.show", {
        id      = "env_bar",
        title   = "§b" .. biome_short .. "  §7|  " .. hp_text,
        percent = hp_fraction,
        color   = (hp_fraction > 0.3) and "blue" or "red",
        style   = "segmented_20",
    })

    -- Заголовок + actionbar
    lore.emit("title.show", {
        title    = time_text,
        subtitle = "§7Биом: " .. biome_short .. "  •  Свет: " .. tostring(w.light),
        fade_in  = 10, stay = 60, fade_out = 20,
    })
    lore.emit("actionbar.set", { text = "§8Время: " .. w.day_time .. "  •  Луна: " .. w.moon_phase })

    -- Звук под настроение
    if w.is_day then
        lore.emit("sound.play", { id = "minecraft:ambient.cave", volume = 0.3, pitch = 1.2 })
    else
        lore.emit("sound.play", { id = "minecraft:entity.bat.ambient", volume = 0.5, pitch = 0.7 })
    end

    -- Маркер на блоке под ногами — цвет зависит от здоровья
    local marker_color = hp_fraction > 0.6 and "#FF00FF00FF" or (hp_fraction > 0.3 and "#FFFFFF8800" or "#FFFF000088")
    lore.emit("marker.set", {
        id    = "env_pos",
        type  = "box",
        x     = math.floor(p.x) + 0.5,
        y     = math.floor(p.y) - 1,
        z     = math.floor(p.z) + 0.5,
        size  = 1,
        color = marker_color,
    })

    -- Снять через 10 секунд
    lore.after(10.0, function()
        lore.emit("bossbar.hide", { id = "env_bar" })
        lore.emit("marker.remove", { id = "env_pos" })
        lore.log("env: убрано")
    end)
end)
