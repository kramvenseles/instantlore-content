-- Геогессер по карте первого сезона — доска с зумом, панорамой и показом результата.
--
-- Открытие: клавиша key.1 (G) или geo.open (тест). Колесо — зум к курсору,
-- перетаскивание ЛКМ — панорама, клик без сдвига — поставить точку, «Сохранить» —
-- доклад geo.guess. Сервер считает промах и шлёт geo.result — тогда доска переходит
-- в РЕЖИМ ПОКАЗА: подводит вид к обоим точкам, рисует правду, твою догадку и линию
-- между ними, снизу — промах/очки. «Дальше» → geo.next → следующий раунд.
--
-- Доска показывает ОКНО большой текстуры (image src_*): зум/панорама — сдвиг окна.
-- Сетка рисуется оверлеем (не вшита), иначе на зуме тонкие линии пропадают.
--
-- ⚠️ WORLD_* и слои LOD должны совпадать с рендером (tools/geoguessr-map): ±20000 мир.

local TEX = 4000
local WORLD_X0, WORLD_X1 = -20000, 20000
local WORLD_Z0, WORLD_Z1 = -20000, 20000
local SPAN = WORLD_X1 - WORLD_X0

-- Слои детализации (LOD): обзор + детальные на области контента. Каждый слой — текстура
-- TEX×TEX, покрывающая квадрат [cx±half, cz±half]. Доска берёт самый ТУГОЙ слой, чей квадрат
-- содержит текущий вид (зум глубже → слой детальнее). Отсортированы туже → шире.
-- Рендерит tools/geoguessr-map/render_map.py; добавить слой = строка сюда + текстура.
-- Движок играет по СЛУЧАЙНЫМ тёплым точкам — персональных близких слоёв (L3) у них нет,
-- поэтому доска пинится на L0–L2 (обзор → центр контента). L1/L2 покрывают обжитую зону,
-- дальний от центра рандом падает на L0 (обзорный). ⚠️ cx/cz/half обязаны совпадать с рендером.
local LEVELS = {
    { tex = "instantlore:textures/gui/s1_map_2.png", cx = 2600, cz = 3900, half = 4000 },
    { tex = "instantlore:textures/gui/s1_map_1.png", cx = 2600, cz = 3900, half = 9000 },
    { tex = "instantlore:textures/gui/s1_map_0.png", cx = 0, cz = 0, half = 20000 },
}

-- палитра меток игроков (цикл по ростеру) — рука/точка
local PLAYER_COLORS = {
    { "#FFFFE08A", "#FF78E6AA" }, { "#FFFF9AA2", "#FFF06A78" },
    { "#FFA6C8FF", "#FF6A9AF0" }, { "#FFC8A6FF", "#FF9A6AF0" },
    { "#FFFFD080", "#FFF0A83A" }, { "#FF9AF0C8", "#FF3AC89A" },
}

-- самый тугой слой, чей квадрат содержит окно вида; последний (обзор) содержит всё
local function pick_level(vcx, vcz, vview)
    local h = vview / 2
    for _, L in ipairs(LEVELS) do
        if vcx - h >= L.cx - L.half and vcx + h <= L.cx + L.half
            and vcz - h >= L.cz - L.half and vcz + h <= L.cz + L.half then
            return L
        end
    end
    return LEVELS[#LEVELS]
end

-- доска по центру экрана; поля вокруг — под подписи осей и панель
local DW, DH = 180, 180
local BX, BY = -90, -90

local MIN_VIEW = 150   -- глубокий зум: у мест есть L3 (2 px/блок), хватает детализации
local ZOOM_STEP = 0.8
local DRAG_SLOP = 4

-- вьюпорт
local view = SPAN
local cx, cz = 0, 0
-- режим: "guess" (угадываем) | "result" (показ правды) | "final" (победный экран)
local mode = "guess"
-- финал: фаза показа и анимация проявления
local final_phase = nil   -- nil | "map" (правда последнего раунда ~4с) | "reveal" (итоги)
local final_cancel = nil  -- таймер авто-перехода map→reveal
local reveal_cancel = nil -- таймер пошагового проявления строк
local revealed = 0        -- сколько мест уже проявлено (снизу вверх)
-- текущая/сохранённая точка догадки
local px, pz = nil, nil
local sx, sz = nil, nil
-- данные результата (в режиме показа)
local R = nil
-- ожидание остальных после своей догадки: {submitted,total}
local waiting = nil
-- жест
local pressed = false
local moved = 0
-- сессия
local active = false   -- идёт ли матч (G открывает доску только внутри матча)
local is_host = false  -- я ведущий? (на экране результата у хоста ещё кнопка «Дальше» — переход без голосования)
local playing = true   -- я участник (угадываю)? false — распорядитель (ведёт, не играет)
local skipvote = nil   -- {votes,total} — голоса за переход (экран результата)
local i_voted = false  -- я уже нажал «Пропустить» на этом экране результата
-- обратный отсчёт до авто-перехода на экране результата (секунды из geo.result.auto)
local result_rem = 0
local result_cancel = nil
local loadbar = false  -- показан ли боссбар загрузки острова
local round_n, round_of = 0, 0
local handle = nil
-- таймер раунда (секунды приходят с сервером в geo.round; 0 — без таймера)
local round_secs = 0
local remaining = 0
local tick_cancel = nil

local function close_screen()
    if handle then handle.close(); handle = nil end
end

-- Игрок сам закрыл доску (Esc). Движок зовёт это только на настоящем close() экрана, НЕ на
-- ре-рендере (там removed()). Обнуляем handle — тогда тики таймера (on_tick/result_tick,
-- гейтятся «if handle») не переоткроют доску: закрыл — осталась закрытой, пока не нажмёшь G.
local function on_user_close()
    handle = nil
end

-- панель загрузки острова (боссбар сверху): прячем, когда раунд начался/матч кончился
local function hide_loadbar()
    if loadbar then lore.emit("bossbar.hide", { id = "geoload" }); loadbar = false end
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

local function clamp_center()
    local half = view / 2
    if view >= SPAN then
        cx, cz = 0, 0
    else
        cx = clamp(cx, WORLD_X0 + half, WORLD_X1 - half)
        cz = clamp(cz, WORLD_Z0 + half, WORLD_Z1 - half)
    end
end

local function nice_step(target)
    for _, s in ipairs({ 250, 500, 1000, 2000, 5000, 10000, 20000 }) do
        if s >= target then return s end
    end
    return 20000
end

-- подвести вид так, чтобы обе точки попали в кадр с ЗАПАСОМ (маркеры и подпись — внутри)
local function frame_two(ax, az, gx, gz)
    local span = math.max(math.abs(ax - gx), math.abs(az - gz)) * 2.4
    view = clamp(span, 2000, SPAN)
    cx = (ax + gx) / 2
    cz = (az + gz) / 2
    clamp_center()
end

-- кадрировать по набору точек { {x,z}, ... } (правда + метки всех игроков)
local function frame_points(pts)
    local minx, maxx, minz, maxz = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ipairs(pts) do
        if p.x < minx then minx = p.x end
        if p.x > maxx then maxx = p.x end
        if p.z < minz then minz = p.z end
        if p.z > maxz then maxz = p.z end
    end
    if minx == math.huge then return end
    local span = math.max(maxx - minx, maxz - minz) * 2.4
    view = clamp(span, 2000, SPAN)
    cx = (minx + maxx) / 2
    cz = (minz + maxz) / 2
    clamp_center()
end

local render

local function world_left() return cx - view / 2 end
local function world_top() return cz - view / 2 end

local function board_px_to_world(bpx, bpy)
    return math.floor(world_left() + bpx / DW * view + 0.5),
           math.floor(world_top() + bpy / DH * view + 0.5)
end

-- мир -> пиксель доски
local function world_to_board(wx, wz)
    return (wx - world_left()) / view * DW, (wz - world_top()) / view * DH
end

-- нажатие над доской: запоминаем жест (и для клика, и для панорамы)
local function on_board_press()
    pressed = true
    moved = 0
end

local function on_drag(d)
    if not pressed then return end
    moved = moved + math.abs(d.dx) + math.abs(d.dy)
    cx = cx - d.dx / DW * view
    cz = cz - d.dy / DH * view
    clamp_center()
    render()
end

local function on_release(p)
    if not pressed then return end
    pressed = false
    -- точку ставим только участник, в режиме угадывания и только если это клик, а не протяжка
    if mode == "guess" and playing and not sx and moved <= DRAG_SLOP then
        local bpx, bpy = p.x - BX, p.y - BY
        if bpx >= 0 and bpx <= DW and bpy >= 0 and bpy <= DH then
            px, pz = board_px_to_world(bpx, bpy)
            render()
        end
    end
end

local function on_zoom(s)
    local bpx, bpy = s.x - BX, s.y - BY
    if bpx < 0 or bpx > DW or bpy < 0 or bpy > DH then return end
    local wl, wt = world_left(), world_top()
    local wxu = wl + bpx / DW * view
    local wzu = wt + bpy / DH * view
    local nv = clamp(view * (s.dir > 0 and ZOOM_STEP or 1 / ZOOM_STEP), MIN_VIEW, SPAN)
    cx = (wxu - bpx / DW * nv) + nv / 2
    cz = (wzu - bpy / DH * nv) + nv / 2
    view = nv
    clamp_center()
    render()
end

local function fmt_time(s)
    if s < 0 then s = 0 end
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function stop_timer()
    if tick_cancel then tick_cancel(); tick_cancel = nil end
end

local function stop_result_timer()
    if result_cancel then result_cancel(); result_cancel = nil end
end

-- тик обратного отсчёта на экране результата: уменьшаем, перерисовываем открытую доску.
-- По нулю не уводим сами — переход делает сервер (geo.round); тикер лишь обновляет цифру.
local function result_tick()
    result_rem = result_rem - 1
    if result_rem <= 0 then
        result_rem = 0
        stop_result_timer()
    end
    if handle and mode == "result" and not pressed then render() end
end

local function start_result_timer(s)
    stop_result_timer()
    result_rem = s or 0
    if result_rem <= 0 then return end
    result_cancel = lore.every(1, result_tick)
end

local function on_save()
    if not playing or not px then return end
    sx, sz = px, pz
    stop_timer()
    lore.report("geo.guess", { x = sx, z = sz })
    lore.log(string.format("geo.guess x=%d z=%d", sx, sz))
    render()
end

-- время вышло: отправить текущую догадку, а нет метки — таймаут (сервер даст 0 очков)
local function on_timeout()
    stop_timer()
    if mode ~= "guess" or not playing then return end
    if px then
        on_save()
    else
        lore.report("geo.guess", { timeout = true })
        lore.log("geo.guess timeout (без метки)")
    end
end

local function on_tick()
    remaining = remaining - 1
    if remaining <= 0 then
        remaining = 0
        on_timeout()
        return
    end
    -- подсказка над хотбаром (видна, когда доска закрыта; обновляется — не гаснет)
    lore.emit("actionbar.set", { text = string.format("§7Место %d/%d · §f%s §7· §eG §7— карта",
        round_n, round_of, fmt_time(remaining)) })
    -- доска открыта и угадываем — обновить таймер на ней (но не рвать активный жест)
    if handle and mode == "guess" and not pressed then render() end
end

local function start_timer(s)
    stop_timer()
    round_secs = s or 0
    remaining = round_secs
    if round_secs <= 0 then return end
    lore.emit("actionbar.set", { text = string.format("§7Место %d/%d · §f%s §7· §eG §7— карта",
        round_n, round_of, fmt_time(remaining)) })
    tick_cancel = lore.every(1, on_tick)
end

local function ui_swallow() pressed = false end

-- крестик-маркер в ДЕТИ clip-группы (координаты board-relative, 0..DW): планки + точка.
-- Обрезка по доске делается группой — за край уходит, геометрию не меняем.
local function marker(ch, bpx, bpy, arm_col, dot_col)
    local mx = math.floor(bpx + 0.5)
    local my = math.floor(bpy + 0.5)
    ch[#ch + 1] = { type = "rect", x = mx - 7, y = my - 1, width = 14, height = 2, background = arm_col }
    ch[#ch + 1] = { type = "rect", x = mx - 1, y = my - 7, width = 2, height = 14, background = arm_col }
    ch[#ch + 1] = { type = "rect", x = mx - 2, y = my - 2, width = 4, height = 4, background = dot_col }
end

-- clip-группа ровно по доске: дети обрезаются по её краю
local function clip_group(children)
    return { type = "group", anchor = "center", x = BX, y = BY, width = DW, height = DH, clip = true, children = children }
end

-- метка: внутри доски — крестик; за краем — стрелка-направление НА краю (не пропадает).
-- Возвращает (x,y) показа в board-коорд (для подписи).
local function place_marker(ch, bpx, bpy, arm_col, dot_col)
    if bpx >= 0 and bpx <= DW and bpy >= 0 and bpy <= DH then
        marker(ch, bpx, bpy, arm_col, dot_col)
        return bpx, bpy
    end
    local ccx, ccy = DW / 2, DH / 2
    local dx, dy = bpx - ccx, bpy - ccy
    local INSET = 2          -- кончик вплотную к краю (не 0 — чтобы крайний пиксель не срезало клипом)
    local tx, ty = math.huge, math.huge
    if dx > 0 then tx = (DW - INSET - ccx) / dx elseif dx < 0 then tx = (INSET - ccx) / dx end
    if dy > 0 then ty = (DH - INSET - ccy) / dy elseif dy < 0 then ty = (INSET - ccy) / dy end
    local t = math.min(tx, ty)
    local ex = math.floor(ccx + dx * t + 0.5)
    local ey = math.floor(ccy + dy * t + 0.5)
    local len = math.max(1, math.sqrt(dx * dx + dy * dy))
    local ux, uy = dx / len, dy / len          -- направление наружу
    local perpx, perpy = -uy, ux
    local L, W = 7, 4
    local bx, by = ex - ux * L, ey - uy * L     -- основание стрелки
    ch[#ch + 1] = { type = "line", x = ex, y = ey, x2 = math.floor(bx + perpx * W + 0.5), y2 = math.floor(by + perpy * W + 0.5), thickness = 1, color = arm_col }
    ch[#ch + 1] = { type = "line", x = ex, y = ey, x2 = math.floor(bx - perpx * W + 0.5), y2 = math.floor(by - perpy * W + 0.5), thickness = 1, color = arm_col }
    ch[#ch + 1] = { type = "rect", x = ex - 1, y = ey - 1, width = 3, height = 3, background = dot_col }
    return ex, ey
end

-- общая часть доски: рамка, окно карты, сетка + подписи осей за доской
local function draw_board(nodes)
    local wl, wt = world_left(), world_top()
    nodes[#nodes + 1] = { type = "rect", anchor = "center", x = BX - 3, y = BY - 3, width = DW + 6, height = DH + 6, background = "#FF0A0C14" }
    local L = pick_level(cx, cz, view)
    local lbpp = TEX / (2 * L.half)        -- px на блок у выбранного слоя
    nodes[#nodes + 1] = { type = "image", anchor = "center", x = BX, y = BY, width = DW, height = DH,
        texture = L.tex, tex_w = TEX, tex_h = TEX,
        src_x = (wl - (L.cx - L.half)) * lbpp, src_y = (wt - (L.cz - L.half)) * lbpp,
        src_w = view * lbpp, src_h = view * lbpp,
        id = "board", on_click = on_board_press }

    local step = nice_step(view / 6)
    local gx = math.ceil(wl / step) * step
    while gx <= wl + view do
        local bpx = (gx - wl) / view * DW
        nodes[#nodes + 1] = { type = "line", anchor = "center", x = BX + bpx, y = BY, x2 = BX + bpx, y2 = BY + DH, thickness = 1, color = "#33FFFFFF" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = BX + bpx, y = BY - 10, align = "center", text = tostring(gx), color = "#FFAEC8E6" }
        gx = gx + step
    end
    local gz = math.ceil(wt / step) * step
    while gz <= wt + view do
        local bpy = (gz - wt) / view * DH
        nodes[#nodes + 1] = { type = "line", anchor = "center", x = BX, y = BY + bpy, x2 = BX + DW, y2 = BY + bpy, thickness = 1, color = "#33FFFFFF" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = BX - 4, y = BY + bpy - 4, align = "right", text = tostring(gz), color = "#FFAEC8E6" }
        gz = gz + step
    end

    if round_of > 0 then
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = BX, y = BY - 20, align = "left", text = string.format("§eРаунд %d/%d", round_n, round_of), color = "#FFFFE08A" }
    end
end

-- режим угадывания: маркеры догадки + правая панель
local function draw_guess(nodes)
    if round_secs > 0 then
        local col = remaining <= 10 and "#FFFF6B6B" or "#FFFFE08A"
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = BX + DW, y = BY - 20, align = "right",
            text = "§l⏳ " .. fmt_time(remaining), color = col }
    end
    local ch = {}
    if sx then local bx, by = world_to_board(sx, sz); place_marker(ch, bx, by, "#FF66E0FF", "#FF3AC8F0") end
    if px then local bx, by = world_to_board(px, pz); place_marker(ch, bx, by, "#FFFFE08A", "#FF78E6AA") end
    nodes[#nodes + 1] = clip_group(ch)

    local PX0, PW = BX + DW + 6, 64
    nodes[#nodes + 1] = { type = "rect", anchor = "center", x = PX0, y = BY, width = PW, height = 108, background = "#E6080A12", id = "panel", on_click = ui_swallow }
    if not playing then
        -- распорядитель: ведёт матч, но не угадывает — только наблюдает
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 4, align = "left", text = "§7Наблюдатель", color = "#FFBFE8FF" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 16, align = "left",
            text = waiting and string.format("§7угадали §f%d/%d", waiting.submitted or 0, waiting.total or 0) or "§8раунд идёт",
            color = "#FFE8EEF8" }
    elseif sx then
        -- догадка отправлена — ждём остальных (счёт из geo.waiting)
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 4, align = "left", text = "§aОтправлено", color = "#FFBFF0C0" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 16, align = "left",
            text = waiting and string.format("§7угадали §f%d/%d", waiting.submitted or 0, waiting.total or 0) or "§7ждём…",
            color = "#FFE8EEF8" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 28, align = "left", text = "§8ждём", color = "#FF9AA0AA" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 37, align = "left", text = "§8остальных", color = "#FF9AA0AA" }
    else
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 4, align = "left", text = "§7Точка", color = "#FFBFE8FF" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 15, align = "left", text = px and ("§fx " .. px) or "§8—", color = "#FFE8EEF8" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 24, align = "left", text = px and ("§fz " .. pz) or "", color = "#FFE8EEF8" }
        nodes[#nodes + 1] = { type = "button", anchor = "center", x = PX0 + 3, y = BY + 38, width = PW - 6, height = 13, text = "Сохранить", enabled = px ~= nil, on_click = on_save }
    end
    -- В фазе угадывания — только «Сохранить». Закрытие/пропуск раунда живёт на экране
    -- результата (между раундами), а не здесь: иначе кнопка скипала бы активный игровой раунд.
end

local TRUTH_ARM, TRUTH_DOT = "#FF66E0FF", "#FF3AC8F0"

-- режим показа: правда + метки ВСЕХ игроков + лидерборд + кнопка (у хоста)
local function draw_result(nodes)
    local truth = R.truth or {}
    local abx, aby = world_to_board(truth.ax or 0, truth.az or 0)

    local ch = {}
    -- метки всех игроков: линия к правде + крестик цветом игрока + подпись ника
    for i, g in ipairs(R.guesses or {}) do
        if not g.nog and g.gx and g.gz then
            local col = PLAYER_COLORS[((i - 1) % #PLAYER_COLORS) + 1]
            local gbx, gby = world_to_board(g.gx, g.gz)
            ch[#ch + 1] = { type = "line", x = gbx, y = gby, x2 = abx, y2 = aby, thickness = 1, color = "#80FFFFFF" }
            local mx, my = place_marker(ch, gbx, gby, col[1], col[2])
            local right = mx > DW * 0.5
            ch[#ch + 1] = { type = "text", x = right and (mx - 8) or (mx + 8), y = my - 4,
                align = right and "right" or "left", text = col[3] or ("§e" .. tostring(g.name or "?")),
                color = col[1] }
        end
    end
    -- правда (бирюзовый); за краем — стрелка-направление
    local adx, ady = place_marker(ch, abx, aby, TRUTH_ARM, TRUTH_DOT)
    local tright = adx > DW * 0.5
    ch[#ch + 1] = { type = "text", x = tright and (adx - 8) or (adx + 8), y = ady - 4,
        align = tright and "right" or "left", text = "§bправда", color = "#FF9AD8FF" }
    nodes[#nodes + 1] = clip_group(ch)

    -- правая панель: лидерборд (имя · «+прибавка» · сумма), первые 8
    local PX0, PW = BX + DW + 6, 92
    local rows = R.board or {}
    local ph = 16 + math.min(#rows, 8) * 10
    nodes[#nodes + 1] = { type = "rect", anchor = "center", x = PX0, y = BY, width = PW, height = ph, background = "#E6080A12", on_click = ui_swallow }
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 4, align = "left",
        text = R["final"] and "§6§lИтог" or "§7Таблица", color = "#FFBFE8FF" }
    for i, row in ipairs(rows) do
        if i > 8 then break end
        local y = BY + 15 + (i - 1) * 10
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = y, align = "left",
            text = string.format("§f%d. %s", i, tostring(row.name or "?")), color = "#FFE8EEF8" }
        -- прибавка за этот раунд (приглушённая), левее суммы
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + PW - 24, y = y, align = "right",
            text = string.format("§7+%d", row.round or 0), color = "#FF8A94A4" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + PW - 4, y = y, align = "right",
            text = string.format("§a%d", row.total or 0), color = "#FFBFF0C0" }
    end

    -- нижняя полоса: только номер раунда. Управление темпом — в правом столбце ПОД таблицей.
    local BARY = BY + DH + 4
    nodes[#nodes + 1] = { type = "rect", anchor = "center", x = BX, y = BARY, width = DW, height = 16, background = "#E6080A12" }
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = BX + 4, y = BARY + 4, align = "left",
        text = R["final"] and "§eПоследнее место" or string.format("§7Раунд §f%d/%d", R.n or 0, R.of or 0),
        color = "#FFE8EEF8" }
    if R["final"] then
        -- финал: без управления — через ~4с сам уйдём на победный экран
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = BX + DW - 4, y = BARY + 4, align = "right",
            text = "§8подводим итоги…", color = "#FF9AA0AA" }
        return
    end

    -- Правый столбец ПОД таблицей (между раундами): таймер авто-перехода + голос за пропуск
    -- (нажали >50% участников — переход сразу), у хоста ещё «Дальше» (мгновенный переход).
    -- Пауза ~20с на обсуждение результата; наблюдатель-распорядитель не голосует.
    local show_vote = playing
    local auto_on = (R.auto and R.auto > 0)
    local vh = 15                                   -- строка таймера
    if show_vote and skipvote then vh = vh + 10 end -- счётчик голосов
    if show_vote then vh = vh + 15 end              -- кнопка «Пропустить»
    if is_host then vh = vh + 15 end                -- кнопка «Дальше»
    local VY = BY + ph + 4
    nodes[#nodes + 1] = { type = "rect", anchor = "center", x = PX0, y = VY, width = PW, height = vh, background = "#E6080A12", on_click = ui_swallow }
    local y = VY + 4
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = y, align = "left",
        text = auto_on and string.format("§7Переход §f%s", fmt_time(result_rem)) or "§7Ждём голосов",
        color = "#FFE8EEF8" }
    y = y + 11
    if show_vote and skipvote then
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = y, align = "left",
            text = string.format("§8%d/%d за пропуск", skipvote.votes or 0, skipvote.total or 0), color = "#FF9AA0AA" }
        y = y + 10
    end
    if show_vote then
        nodes[#nodes + 1] = { type = "button", anchor = "center", x = PX0 + 3, y = y, width = PW - 6, height = 13,
            text = i_voted and "§aГолос учтён" or "Пропустить", enabled = not i_voted,
            on_click = function()
                i_voted = true
                lore.report("geo.vote", {})
                render()
            end }
        y = y + 15
    end
    if is_host then
        nodes[#nodes + 1] = { type = "button", anchor = "center", x = PX0 + 3, y = y, width = PW - 6, height = 13,
            text = "Дальше",
            on_click = function()
                lore.report("geo.next", {})
                close_screen()
            end }
    end
end

-- победный экран: тёмный задник, строки проявляются снизу вверх, победитель — последним.
-- revealed растёт по таймеру; ранг виден, когда rank > N - revealed (т.е. с последнего места).
local FROW_W = 168
local function draw_final(nodes)
    local rows = R.board or {}
    local N = math.min(#rows, 8)
    local RX = -FROW_W / 2
    nodes[#nodes + 1] = { type = "rect", anchor = "center", x = -140, y = -104, width = 280, height = 208, background = "#EE05060C", on_click = ui_swallow }
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = 0, y = -92, align = "center", text = "§6§lИТОГИ МАТЧА", color = "#FFFFD86A" }

    local function row_at(rank, y, win)
        local row = rows[rank]
        if not row then return end
        if win then
            nodes[#nodes + 1] = { type = "rect", anchor = "center", x = RX - 2, y = y - 3, width = FROW_W + 4, height = 14, background = "#55FFC24A" }
        end
        local label = (win and "§6§l✦ " or "§f") .. string.format("%d. %s", rank, tostring(row.name or "?"))
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = RX + 4, y = y, align = "left",
            text = label, color = win and "#FFFFE89A" or "#FFE8EEF8" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = RX + FROW_W - 28, y = y, align = "right",
            text = string.format("§7+%d", row.round or 0), color = "#FF8A94A4" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = RX + FROW_W - 4, y = y, align = "right",
            text = string.format("§a%d", row.total or 0), color = "#FFBFF0C0" }
    end

    local function visible(rank) return rank > (N - revealed) end
    local WINY = -58

    -- победитель сверху + подпись (появляется последним)
    if N >= 1 and visible(1) then
        row_at(1, WINY, true)
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = 0, y = WINY + 11, align = "center",
            text = "§eПобедитель", color = "#FFFFE08A" }
    end
    -- остальные места ниже (2..N)
    for rank = 2, N do
        if visible(rank) then
            row_at(rank, WINY + 30 + (rank - 2) * 12, false)
        end
    end

    -- кнопка появляется, когда все проявились: «Выйти» доступна КАЖДОМУ (geo.leave — выход
    -- только для себя; матч сам закроется через авто-таймер или когда вышли все). Вместо
    -- прежнего хост-«Готово», чтобы никто не ждал ведущего на финале.
    if revealed >= N then
        local BY2 = WINY + 30 + math.max(N - 1, 1) * 12 + 6
        nodes[#nodes + 1] = { type = "button", anchor = "center", x = -28, y = BY2, width = 56, height = 14,
            text = "Выйти",
            on_click = function()
                lore.report("geo.leave", {})
                close_screen()
            end }
    end
end

render = function()
    clamp_center()
    local nodes = {}
    if mode == "final" then
        draw_final(nodes)
    else
        draw_board(nodes)
        if mode == "result" then draw_result(nodes) else draw_guess(nodes) end
    end
    handle = lore.screen({
        title = "Карта первого сезона",
        nodes = nodes,
        on_scroll = on_zoom,
        on_drag = on_drag,
        on_release = on_release,
        on_close = on_user_close,
    })
end

-- сбросить таймеры финала (переход, проявление)
local function stop_final()
    if final_cancel then final_cancel(); final_cancel = nil end
    if reveal_cancel then reveal_cancel(); reveal_cancel = nil end
end

-- один шаг проявления: +1 место (снизу вверх), звук; победитель — особым звуком
local function reveal_tick()
    local N = math.min(#(R.board or {}), 8)
    revealed = revealed + 1
    if revealed >= N then
        revealed = N
        lore.emit("sound.play", { id = "minecraft:ui.toast.challenge_complete", category = "master", volume = 0.7, pitch = 1.0 })
        if reveal_cancel then reveal_cancel(); reveal_cancel = nil end
    else
        lore.emit("sound.play", { id = "minecraft:block.note_block.pling", category = "master",
            volume = 0.6, pitch = math.min(0.8 + 0.12 * revealed, 2.0) })
    end
    render()
end

-- перейти с карты последнего раунда на победный экран
local function start_reveal()
    final_cancel = nil
    if reveal_cancel then reveal_cancel(); reveal_cancel = nil end
    mode = "final"
    final_phase = "reveal"
    revealed = 0
    local N = math.min(#((R and R.board) or {}), 8)
    reveal_tick() -- первое место (последнее в таблице) сразу
    if revealed < N then
        reveal_cancel = lore.every(0.6, reveal_tick)
    end
end

-- G/geo.open: просто показать ТЕКУЩЕЕ состояние (угадывание/ожидание/результат/финал).
-- Сброс в свежее угадывание делает ТОЛЬКО geo.round — иначе повторное открытие после отправки
-- догадки кидало бы в новое угадывание вместо экрана результата.
local function open()
    render()
end

-- результат раунда с сервера: правда + метки всех игроков + лидерборд
lore.on("geo.result", function(d)
    stop_timer()
    stop_final()
    stop_result_timer()
    active = true   -- результат приходит только внутри матча; держим G рабочим и на реконнекте в фазе показа
    is_host = d.host == true
    R = d
    mode = "result"
    final_phase = nil
    waiting = nil
    skipvote = nil   -- свежий экран результата — голоса за переход с нуля
    i_voted = false
    px, pz, sx, sz = nil, nil, nil, nil
    -- кадр по всем точкам: правда + догадки всех (у кого есть метка)
    local pts = {}
    if d.truth then pts[#pts + 1] = { x = d.truth.ax, z = d.truth.az } end
    for _, g in ipairs(d.guesses or {}) do
        if g.gx and g.gz then pts[#pts + 1] = { x = g.gx, z = g.gz } end
    end
    frame_points(pts)
    render()
    -- финал: показать правду последнего раунда ~4с, затем сам уйти на победный экран
    if d["final"] then
        final_phase = "map"
        final_cancel = lore.after(4, start_reveal)
    else
        -- между раундами: обратный отсчёт до авто-перехода (сервер уведёт по d.auto сек)
        start_result_timer(d.auto or 0)
    end
end)

-- сколько игроков уже угадали (показываем ожидающему)
lore.on("geo.waiting", function(d)
    waiting = d
    if handle and mode == "guess" then render() end
end)

-- сколько проголосовало за переход (экран результата) / пропуск (угадывание)
lore.on("geo.skipvote", function(d)
    skipvote = d
    if handle and (mode == "guess" or mode == "result") then render() end
end)

-- прогресс загрузки острова (пока режется — панель-боссбар сверху, «N/256»)
lore.on("geo.loading", function(d)
    local done, total = d.done or 0, d.total or 1
    local pct = total > 0 and (done / total) or 0
    local title = string.format("§eЗагрузка острова §f%d/%d", done, total)
    if not loadbar then
        lore.emit("bossbar.show", { id = "geoload", title = title, percent = pct, color = "purple" })
        loadbar = true
    else
        lore.emit("bossbar.set", { id = "geoload", title = title, percent = pct })
    end
end)

-- новый раунд: свежее угадывание, экран закрыть (игрок осматривается), таймер пошёл
lore.on("geo.round", function(d)
    stop_final()
    stop_result_timer()
    hide_loadbar()   -- раунд начался → остров загружен, панель убрать
    active = true
    is_host = d.host == true
    playing = d.play ~= false   -- распорядитель: play=false (наблюдает, не угадывает)
    skipvote = nil
    i_voted = false
    round_n, round_of = d.n or 0, d.of or 0
    mode = "guess"
    final_phase = nil
    view, cx, cz, px, pz, sx, sz, R, waiting = SPAN, 0, 0, nil, nil, nil, nil, nil, nil
    pressed, moved = false, 0
    close_screen()
    start_timer(d.secs or 0)
    -- без таймера подсказку всё равно показать (start_timer молчит при secs<=0)
    if (d.secs or 0) <= 0 then
        lore.emit("actionbar.set", { text = string.format("§7Место %d/%d · §eнажми §fG§e — открыть карту", round_n, round_of) })
    end
end)

-- стал ведущим (прежний хост вышел) — показать host-кнопку в любом режиме
-- («закрыть место» в угадывании, «Дальше»/«Готово» на показе/финале)
lore.on("geo.host", function()
    is_host = true
    if R then R.host = true end
    if handle then render() end
end)

-- матч кончился: закрыть доску, погасить таймеры и подсказку, G больше не открывает
lore.on("geo.end", function()
    active = false
    is_host = false
    playing = true
    skipvote = nil
    i_voted = false
    hide_loadbar()
    stop_timer()
    stop_final()
    stop_result_timer()
    mode = "guess"
    final_phase = nil
    R, waiting = nil, nil
    close_screen()
    lore.emit("actionbar.set", { text = "" })
end)

lore.on("geo.open", open)                                  -- тест/ручное открытие
lore.on("key.1", function() if active then open() end end) -- G — только в активном матче
