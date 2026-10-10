-- Геогессер по карте первого сезона — доска с зумом.
--
-- Открытие: клавиша key.1 (по умолчанию G) ИЛИ событие geo.open (для теста).
-- Колесо мыши — зум к курсору; клик по карте — отметить догадку; «Подтвердить» —
-- доклад geo.guess серверу (телепорт раундов и счёт по расстоянию считает сервер).
--
-- Модель: вьюпорт = центр мира (cx,cz) + сторона окна в блоках (view). Доска показывает
-- КУСОК большой текстуры карты (image с src_*), поэтому зум/панорама — это сдвиг окна,
-- а не замена картинки.
--
-- ⚠️ WORLD_* и TEX обязаны совпадать с картинкой (gen_placeholder_map2.py):
-- барьер ±20000, текстура 4000px. Разъедутся — клик промахнётся.

local MAP = "instantlore:textures/gui/s1_map.png"
local TEX = 4000                      -- сторона текстуры в пикселях
local WORLD_X0, WORLD_X1 = -20000, 20000
local WORLD_Z0, WORLD_Z1 = -20000, 20000
local SPAN = WORLD_X1 - WORLD_X0       -- 40000
local BPP = TEX / SPAN                  -- пикселей текстуры на блок (0.1)

-- доска на экране: квадрат, по центру (центро-якорь)
local DW, DH = 188, 188
local BX, BY = -94, -92                 -- левый-верхний угол доски от центра экрана

local MIN_VIEW = 800                    -- самый близкий зум (блоков поперёк доски)
local ZOOM_STEP = 0.8                   -- во сколько раз меняет view один щелчок колеса

-- состояние вьюпорта (живёт между перерисовками в пределах раунда)
local view = SPAN
local cx, cz = 0, 0
local gx, gz = nil, nil                 -- догадка в мировых координатах (или nil)

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

-- держим окно внутри барьера
local function clamp_center()
    local half = view / 2
    if view >= SPAN then
        cx, cz = 0, 0
    else
        cx = clamp(cx, WORLD_X0 + half, WORLD_X1 - half)
        cz = clamp(cz, WORLD_Z0 + half, WORLD_Z1 - half)
    end
end

local render -- предварительное объявление

-- клик по доске (пиксель от угла) -> мир
local function board_to_world(bpx, bpy)
    local wl = cx - view / 2
    local wt = cz - view / 2
    return math.floor(wl + bpx / DW * view + 0.5),
           math.floor(wt + bpy / DH * view + 0.5)
end

local function on_map_click(_, click)
    if not click then return end
    gx, gz = board_to_world(click.x, click.y)
    render()
end

local function on_zoom(scroll)
    if not scroll then return end
    -- курсор в пикселях доски (scroll.x/y отсчитаны от центра экрана, доска — от BX,BY)
    local bpx, bpy = scroll.x - BX, scroll.y - BY
    if bpx < 0 or bpx > DW or bpy < 0 or bpy > DH then return end

    local wl, wt = cx - view / 2, cz - view / 2
    local wxu = wl + bpx / DW * view         -- мир под курсором (до зума)
    local wzu = wt + bpy / DH * view
    local nv = clamp(view * (scroll.dir > 0 and ZOOM_STEP or 1 / ZOOM_STEP), MIN_VIEW, SPAN)
    -- вернуть тот же мир под курсор после смены масштаба
    cx = (wxu - bpx / DW * nv) + nv / 2
    cz = (wzu - bpy / DH * nv) + nv / 2
    view = nv
    clamp_center()
    render()
end

local function on_confirm()
    if not gx then return end
    lore.report("geo.guess", { x = gx, z = gz })
    lore.log(string.format("geo.guess x=%d z=%d", gx, gz))
end

render = function()
    clamp_center()
    local wl, wt = cx - view / 2, cz - view / 2

    local nodes = {
        -- рамка-подложка чуть больше доски
        { type = "rect", anchor = "center", x = BX - 3, y = BY - 3, width = DW + 6, height = DH + 6,
          background = "#FF0A0C14" },

        -- доска: окно текстуры (src_*), кликабельна; зум — on_scroll экрана
        { type = "image", anchor = "center", x = BX, y = BY, width = DW, height = DH,
          texture = MAP, tex_w = TEX, tex_h = TEX,
          src_x = (wl - WORLD_X0) * BPP, src_y = (wt - WORLD_Z0) * BPP,
          src_w = view * BPP, src_h = view * BPP,
          id = "board", on_click = on_map_click },

        -- верхняя полоса + заголовок
        { type = "rect", anchor = "center", x = BX, y = BY, width = DW, height = 14,
          background = "#AA0A0C14" },
        { type = "text", anchor = "center", x = 0, y = BY + 3, align = "center",
          text = "§bКуда это?  §7колесо — зум · клик — отметить", color = "#FFBFE8FF" },

        -- нижняя полоса
        { type = "rect", anchor = "center", x = BX, y = BY + DH - 15, width = DW, height = 15,
          background = "#AA0A0C14" },
    }

    if gx then
        -- маркер догадки: пересчитывается из мира под текущий вьюпорт
        local bpx = (gx - wl) / view * DW
        local bpy = (gz - wt) / view * DH
        if bpx >= 0 and bpx <= DW and bpy >= 0 and bpy <= DH then
            local mx, my = BX + bpx, BY + bpy
            nodes[#nodes + 1] = { type = "line", anchor = "center",
                x = mx - 6, y = my, x2 = mx + 6, y2 = my, thickness = 1, color = "#FFFFE08A" }
            nodes[#nodes + 1] = { type = "line", anchor = "center",
                x = mx, y = my - 6, x2 = mx, y2 = my + 6, thickness = 1, color = "#FFFFE08A" }
            nodes[#nodes + 1] = { type = "rect", anchor = "center",
                x = mx - 2, y = my - 2, width = 4, height = 4, background = "#FF78E6AA" }
        end

        nodes[#nodes + 1] = { type = "text", anchor = "center", x = BX + 4, y = BY + DH - 11,
            align = "left", text = string.format("§fx %d  z %d", gx, gz), color = "#FFE8EEF8" }
        nodes[#nodes + 1] = { type = "button", anchor = "center", x = BX + DW - 82, y = BY + DH - 13,
            width = 78, height = 13, text = "Подтвердить", on_click = on_confirm }
    else
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = 0, y = BY + DH - 11,
            align = "center", text = "§8кликни по карте, где это", color = "#FF7A8A9A" }
    end

    lore.screen({ title = "Карта первого сезона", nodes = nodes, on_scroll = on_zoom })
end

local function open()
    view, cx, cz, gx, gz = SPAN, 0, 0, nil, nil
    render()
end

lore.on("geo.open", open)   -- тест
lore.on("key.1", open)      -- клавиша G
