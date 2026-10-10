-- Геогессер по карте первого сезона — доска с зумом и панорамой.
--
-- Открытие: клавиша key.1 (G) или geo.open (тест). Колесо — зум к курсору.
-- Перетаскивание ЛКМ — панорама. Клик без сдвига — поставить точку. «Сохранить» —
-- зафиксировать и доложить geo.guess (счёт по расстоянию считает сервер).
--
-- Доска показывает ОКНО большой текстуры (image src_*). Сетка рисуется оверлеем
-- (line-узлы по вьюпорту), а не вшита в картинку, — иначе на зуме тонкие линии
-- пропадают при выборке.
--
-- ⚠️ WORLD_* и TEX должны совпадать с картинкой (gen_placeholder_map2.py): ±20000, 4000px.

local MAP = "instantlore:textures/gui/s1_map.png"
local TEX = 4000
local WORLD_X0, WORLD_X1 = -20000, 20000
local WORLD_Z0, WORLD_Z1 = -20000, 20000
local SPAN = WORLD_X1 - WORLD_X0
local BPP = TEX / SPAN

-- доска строго по центру экрана
local DW, DH = 200, 200
local BX, BY = -100, -100

local MIN_VIEW = 600
local ZOOM_STEP = 0.8
local DRAG_SLOP = 4         -- сдвиг больше этого (px) = пан, а не клик

-- вьюпорт
local view = SPAN
local cx, cz = 0, 0
-- текущая (ещё не сохранённая) точка и сохранённая
local px, pz = nil, nil
local sx, sz = nil, nil
-- жест
local pressed = false
local moved = 0

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

-- «красивый» шаг сетки: ~6 делений на окно
local function nice_step(target)
    for _, s in ipairs({ 250, 500, 1000, 2000, 5000, 10000, 20000 }) do
        if s >= target then return s end
    end
    return 20000
end

local render

-- мир <-> доска (пиксель от левого-верхнего угла доски)
local function world_left() return cx - view / 2 end
local function world_top() return cz - view / 2 end

local function board_px_to_world(bpx, bpy)
    return math.floor(world_left() + bpx / DW * view + 0.5),
           math.floor(world_top() + bpy / DH * view + 0.5)
end

-- нажатие над доской (ЛКМ вниз): запоминаем жест, точку ставим на отпускании
local function on_board_press()
    pressed = true
    moved = 0
end

local function on_drag(d)
    if not pressed then return end
    moved = moved + math.abs(d.dx) + math.abs(d.dy)
    -- тащим карту за курсором: окно едет в обратную сторону
    cx = cx - d.dx / DW * view
    cz = cz - d.dy / DH * view
    clamp_center()
    render()
end

local function on_release(p)
    if not pressed then return end
    pressed = false
    if moved <= DRAG_SLOP then
        -- чистый клик — курсор от центра экрана; доска стоит в BX,BY
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

local function on_save()
    if not px then return end
    sx, sz = px, pz
    lore.report("geo.guess", { x = sx, z = sz })
    lore.log(string.format("geo.guess x=%d z=%d", sx, sz))
    render()
end

local function ui_swallow() pressed = false end  -- нажатие по панели — не по карте

-- маркер-крестик с точкой в центре доски (bpx,bpy), цвета заданы
local function marker(nodes, bpx, bpy, line_col, dot_col)
    if bpx < 0 or bpx > DW or bpy < 0 or bpy > DH then return end
    local mx, my = BX + bpx, BY + bpy
    nodes[#nodes + 1] = { type = "line", anchor = "center", x = mx - 6, y = my, x2 = mx + 6, y2 = my, thickness = 1, color = line_col }
    nodes[#nodes + 1] = { type = "line", anchor = "center", x = mx, y = my - 6, x2 = mx, y2 = my + 6, thickness = 1, color = line_col }
    nodes[#nodes + 1] = { type = "rect", anchor = "center", x = mx - 2, y = my - 2, width = 4, height = 4, background = dot_col }
end

render = function()
    clamp_center()
    local wl, wt = world_left(), world_top()

    local nodes = {
        { type = "rect", anchor = "center", x = BX - 3, y = BY - 3, width = DW + 6, height = DH + 6, background = "#FF0A0C14" },
        { type = "image", anchor = "center", x = BX, y = BY, width = DW, height = DH,
          texture = MAP, tex_w = TEX, tex_h = TEX,
          src_x = (wl - WORLD_X0) * BPP, src_y = (wt - WORLD_Z0) * BPP,
          src_w = view * BPP, src_h = view * BPP,
          id = "board", on_click = on_board_press },
    }

    -- сетка оверлеем + подписи осей
    local step = nice_step(view / 6)
    local gx = math.ceil(wl / step) * step
    while gx <= wl + view do
        local bpx = (gx - wl) / view * DW
        nodes[#nodes + 1] = { type = "line", anchor = "center", x = BX + bpx, y = BY, x2 = BX + bpx, y2 = BY + DH, thickness = 1, color = "#33FFFFFF" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = BX + bpx + 1, y = BY + 1, align = "left", text = "§8" .. gx, color = "#80AEC8E6" }
        gx = gx + step
    end
    local gz = math.ceil(wt / step) * step
    while gz <= wt + view do
        local bpy = (gz - wt) / view * DH
        nodes[#nodes + 1] = { type = "line", anchor = "center", x = BX, y = BY + bpy, x2 = BX + DW, y2 = BY + bpy, thickness = 1, color = "#33FFFFFF" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = BX + 1, y = BY + bpy + 1, align = "left", text = "§8" .. gz, color = "#80AEC8E6" }
        gz = gz + step
    end

    -- сохранённая точка (бирюзовый) и текущая (жёлто-зелёный)
    if sx then marker(nodes, (sx - wl) / view * DW, (sz - wt) / view * DH, "#FF66E0FF", "#FF3AC8F0") end
    if px then marker(nodes, (px - wl) / view * DW, (pz - wt) / view * DH, "#FFFFE08A", "#FF78E6AA") end

    -- правая панель (поверх угла доски): текущая точка, кнопка, сохранённое
    local PX0, PW = 36, 62
    nodes[#nodes + 1] = { type = "rect", anchor = "center", x = PX0, y = 26, width = PW, height = 82, background = "#E6080A12", id = "panel", on_click = ui_swallow }
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = 30, align = "left", text = "§7Точка", color = "#FFBFE8FF" }
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = 40, align = "left", text = px and ("§fx " .. px) or "§8—", color = "#FFE8EEF8" }
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = 49, align = "left", text = px and ("§fz " .. pz) or "", color = "#FFE8EEF8" }
    nodes[#nodes + 1] = { type = "button", anchor = "center", x = PX0 + 3, y = 60, width = PW - 6, height = 13, text = "Сохранить", enabled = px ~= nil, on_click = on_save }
    if sx then
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = 78, align = "left", text = "§aСохранено", color = "#FF88E6AA" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = 88, align = "left", text = "§ax " .. sx, color = "#FF88E6AA" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = 97, align = "left", text = "§az " .. sz, color = "#FF88E6AA" }
    end

    lore.screen({
        title = "Карта первого сезона",
        nodes = nodes,
        on_scroll = on_zoom,
        on_drag = on_drag,
        on_release = on_release,
    })
end

local function open()
    view, cx, cz, px, pz, sx, sz, pressed, moved = SPAN, 0, 0, nil, nil, nil, nil, false, 0
    render()
end

lore.on("geo.open", open)
lore.on("key.1", open)
