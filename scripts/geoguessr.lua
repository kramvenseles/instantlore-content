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

-- доска по центру экрана; поля вокруг — под подписи осей и панель
local DW, DH = 180, 180
local BX, BY = -90, -90

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
-- сессия раундов (приходит с сервера)
local round_n, round_of = 0, 0
local handle = nil           -- хэндл открытого экрана (чтобы закрыть)

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

-- маркер-крестик по центру (bpx,bpy): симметричные планки на rect'ах + точка
local function marker(nodes, bpx, bpy, arm_col, dot_col)
    if bpx < 0 or bpx > DW or bpy < 0 or bpy > DH then return end
    local mx = BX + math.floor(bpx + 0.5)
    local my = BY + math.floor(bpy + 0.5)
    nodes[#nodes + 1] = { type = "rect", anchor = "center", x = mx - 7, y = my - 1, width = 14, height = 2, background = arm_col }
    nodes[#nodes + 1] = { type = "rect", anchor = "center", x = mx - 1, y = my - 7, width = 2, height = 14, background = arm_col }
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

    -- сетка оверлеем на доске; подписи осей — ЗА доской (X сверху, Z слева)
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

    -- сохранённая точка (бирюзовый) и текущая (жёлто-зелёный)
    if sx then marker(nodes, (sx - wl) / view * DW, (sz - wt) / view * DH, "#FF66E0FF", "#FF3AC8F0") end
    if px then marker(nodes, (px - wl) / view * DW, (pz - wt) / view * DH, "#FFFFE08A", "#FF78E6AA") end

    -- панель СПРАВА ОТ доски (в поле, не поверх карты): текущая точка, кнопка, сохранённое
    local PX0, PW = BX + DW + 6, 64
    nodes[#nodes + 1] = { type = "rect", anchor = "center", x = PX0, y = BY, width = PW, height = 108, background = "#E6080A12", id = "panel", on_click = ui_swallow }
    if round_of > 0 then
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = BX, y = BY - 20, align = "left", text = string.format("§eРаунд %d/%d", round_n, round_of), color = "#FFFFE08A" }
    end
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 4, align = "left", text = "§7Точка", color = "#FFBFE8FF" }
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 15, align = "left", text = px and ("§fx " .. px) or "§8—", color = "#FFE8EEF8" }
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 24, align = "left", text = px and ("§fz " .. pz) or "", color = "#FFE8EEF8" }
    nodes[#nodes + 1] = { type = "button", anchor = "center", x = PX0 + 3, y = BY + 38, width = PW - 6, height = 13, text = "Сохранить", enabled = px ~= nil, on_click = on_save }
    if sx then
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 62, align = "left", text = "§aСохранено", color = "#FF88E6AA" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 72, align = "left", text = "§ax " .. sx, color = "#FF88E6AA" }
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = PX0 + 5, y = BY + 81, align = "left", text = "§az " .. sz, color = "#FF88E6AA" }
    end

    handle = lore.screen({
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

-- экран результата раунда (поверх): промах, очки, всего, кнопка дальше/готово
local function show_result(d)
    local last = d["final"]
    local nodes = {
        { type = "rect", anchor = "center", x = -80, y = -56, width = 160, height = 112, background = "#F00A0C14" },
        { type = "text", anchor = "center", x = 0, y = -48, align = "center", text = string.format("§eРаунд %d/%d", d.n or 0, d.of or 0), color = "#FFFFE08A" },
        { type = "text", anchor = "center", x = 0, y = -34, align = "center", text = "§7это §f" .. tostring(d.name or "?"), color = "#FFE8EEF8" },
        { type = "text", anchor = "center", x = 0, y = -16, align = "center", text = string.format("§7промах  §f%d §7бл", d.dist or 0), color = "#FFCCD4E6" },
        { type = "text", anchor = "center", x = 0, y = -2, align = "center", text = string.format("§a+%d §7очков", d.points or 0), color = "#FF88E6AA" },
        { type = "text", anchor = "center", x = 0, y = 14, align = "center", text = string.format("§7всего  §f%d", d.total or 0), color = "#FFE8EEF8" },
        { type = "button", anchor = "center", x = -40, y = 34, width = 80, height = 14,
          text = last and "Готово" or "Дальше",
          on_click = function()
              lore.report(last and "geo.done" or "geo.next", {})
              close_screen()
          end },
    }
    handle = lore.screen({ title = "Результат", nodes = nodes })
end

-- новый раунд с сервера: свежее состояние, экран закрыть (игрок осматривается)
lore.on("geo.round", function(d)
    round_n, round_of = d.n or 0, d.of or 0
    view, cx, cz, px, pz, sx, sz = SPAN, 0, 0, nil, nil, nil, nil
    close_screen()
end)

lore.on("geo.result", function(d) show_result(d) end)

lore.on("geo.open", function() show_result({n=1,of=3,name="база",dist=212,points=931,total=931,["final"]=false}) end)  -- ТЕСТ
lore.on("key.1", open)
