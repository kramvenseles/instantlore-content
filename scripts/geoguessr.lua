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
local LEVELS = {
    { tex = "instantlore:textures/gui/s1_map_2.png", cx = 2600, cz = 3900, half = 4000 },
    { tex = "instantlore:textures/gui/s1_map_1.png", cx = 2600, cz = 3900, half = 9000 },
    { tex = "instantlore:textures/gui/s1_map_0.png", cx = 0, cz = 0, half = 20000 },
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

local MIN_VIEW = 600
local ZOOM_STEP = 0.8
local DRAG_SLOP = 4

-- вьюпорт
local view = SPAN
local cx, cz = 0, 0
-- режим: "guess" (угадываем) | "result" (показ правды)
local mode = "guess"
-- текущая/сохранённая точка догадки
local px, pz = nil, nil
local sx, sz = nil, nil
-- данные результата (в режиме показа)
local R = nil
-- жест
local pressed = false
local moved = 0
-- сессия
local round_n, round_of = 0, 0
local handle = nil
-- таймер раунда (секунды приходят с сервером в geo.round; 0 — без таймера)
local round_secs = 0
local remaining = 0
local tick_cancel = nil

local function close_screen()
    if handle then handle.close(); handle = nil end
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
    -- точку ставим только в режиме угадывания и только если это клик, а не протяжка
    if mode == "guess" and moved <= DRAG_SLOP then
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

local function on_save()
    if not px then return end
    sx, sz = px, pz
    stop_timer()
    lore.report("geo.guess", { x = sx, z = sz })
    lore.log(string.format("geo.guess x=%d z=%d", sx, sz))
    render()
end

-- время вышло: отправить текущую догадку, а нет метки — таймаут (сервер даст 0 очков)
local function on_timeout()
    stop_timer()
    if mode ~= "guess" then return end
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
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 4, align = "left", text = "§7Точка", color = "#FFBFE8FF" }
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 15, align = "left", text = px and ("§fx " .. px) or "§8—", color = "#FFE8EEF8" }
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 24, align = "left", text = px and ("§fz " .. pz) or "", color = "#FFE8EEF8" }
    nodes[#nodes + 1] = { type = "button", anchor = "center", x = PX0 + 3, y = BY + 38, width = PW - 6, height = 13, text = "Сохранить", enabled = px ~= nil, on_click = on_save }
end

-- режим показа: правда + догадка + линия + нижняя полоса со счётом
local function draw_result(nodes)
    local wl, wt = world_left(), world_top()
    -- истинные позиции (board-relative); за край доски — обрежет clip-группа
    local abx, aby = world_to_board(R.ax, R.az)

    local ch = {}
    -- догадка (есть только если не таймаут-без-метки): линия к правде + жёлтая метка
    if not R.nog then
        local gbx, gby = world_to_board(R.gx, R.gz)
        ch[#ch + 1] = { type = "line", x = gbx, y = gby, x2 = abx, y2 = aby, thickness = 1, color = "#C0FFFFFF" }
        place_marker(ch, gbx, gby, "#FFFFE08A", "#FF78E6AA")
    end
    -- правда (бирюзовый); за краем — стрелка-направление
    local adx, ady = place_marker(ch, abx, aby, "#FF66E0FF", "#FF3AC8F0")
    -- подпись места у ПОКАЗАННОЙ точки правды (у стрелки, если она за краем)
    local right = adx > DW * 0.5
    ch[#ch + 1] = { type = "text", x = right and (adx - 8) or (adx + 8), y = ady - 4,
        align = right and "right" or "left", text = "§b" .. tostring(R.name or "?"), color = "#FF9AD8FF" }
    nodes[#nodes + 1] = clip_group(ch)

    -- нижняя полоса: промах · очки (всего — на финале крупно), кнопка справа
    local BARY = BY + DH + 4
    nodes[#nodes + 1] = { type = "rect", anchor = "center", x = BX, y = BARY, width = DW, height = 16, background = "#E6080A12" }
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = BX + 4, y = BARY + 4, align = "left",
        text = R["final"]
            and string.format("§eИтог: §f%d §7очков", R.total or 0)
            or (R.nog
                and string.format("§cВремя вышло §7· §a+%d", R.points or 0)
                or string.format("§7промах §f%d §7бл   §a+%d", R.dist or 0, R.points or 0)),
        color = "#FFE8EEF8" }
    nodes[#nodes + 1] = { type = "button", anchor = "center", x = BX + DW - 46, y = BARY + 1, width = 46, height = 14,
        text = R["final"] and "Готово" or "Дальше",
        on_click = function()
            lore.report(R["final"] and "geo.done" or "geo.next", {})
            close_screen()
        end }
    -- бегущий счёт — компактно над полосой справа (не перекрывается кнопкой)
    if not R["final"] then
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = BX + DW, y = BY - 20, align = "right",
            text = string.format("§7всего §f%d", R.total or 0), color = "#FFE8EEF8" }
    end
end

render = function()
    clamp_center()
    local nodes = {}
    draw_board(nodes)
    if mode == "result" then draw_result(nodes) else draw_guess(nodes) end
    handle = lore.screen({
        title = "Карта первого сезона",
        nodes = nodes,
        on_scroll = on_zoom,
        on_drag = on_drag,
        on_release = on_release,
    })
end

local function open()
    mode = "guess"
    view, cx, cz, px, pz, sx, sz, pressed, moved = SPAN, 0, 0, nil, nil, nil, nil, false, 0
    render()
end

-- результат раунда с сервера: показать на карте
lore.on("geo.result", function(d)
    stop_timer()
    R = d
    mode = "result"
    px, pz, sx, sz = nil, nil, nil, nil
    -- нет догадки (таймаут без метки) — кадрируем на правду
    if d.nog then frame_two(d.ax, d.az, d.ax, d.az) else frame_two(d.ax, d.az, d.gx, d.gz) end
    render()
end)

-- новый раунд: свежее угадывание, экран закрыть (игрок осматривается), таймер пошёл
lore.on("geo.round", function(d)
    round_n, round_of = d.n or 0, d.of or 0
    mode = "guess"
    view, cx, cz, px, pz, sx, sz, R = SPAN, 0, 0, nil, nil, nil, nil, nil
    close_screen()
    start_timer(d.secs or 0)
    -- без таймера подсказку всё равно показать (start_timer молчит при secs<=0)
    if (d.secs or 0) <= 0 then
        lore.emit("actionbar.set", { text = string.format("§7Место %d/%d · §eнажми §fG§e — открыть карту", round_n, round_of) })
    end
end)

lore.on("geo.open", open)
lore.on("key.1", open)
