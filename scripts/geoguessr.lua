-- Геогессер по карте первого сезона — обкатка механики.
--
-- Событие geo.open открывает полноэкранную карту-доску. Клик по карте ставит маркер
-- и переводит пиксель в мировые координаты; «Подтвердить» докладывает догадку серверу
-- (geo.guess). Телепорт по раундам и счёт по расстоянию добавит серверная сторона —
-- здесь живёт только доска и перевод клика в координаты.
--
-- Тест:  /lore emit to <Ник> geo.open
--
-- ⚠️ Рамка мира WORLD_* обязана совпадать с рамкой, по которой нарисована доска
-- (s1_map.png генерится gen_placeholder_map.py с теми же числами). Разъедутся —
-- клик будет попадать мимо.

local MAP = "instantlore:textures/gui/s1_map.png"

-- рамка мира (блоки), та же что у картинки
local WORLD_X0, WORLD_X1 = -5000, 10000
local WORLD_Z0, WORLD_Z1 = -3000, 7000

-- размер доски на экране (пиксели GUI); клик приходит в [0,DW)x[0,DH)
local DW, DH = 300, 180
-- левый-верхний угол доски — смещение от центра экрана
local BX, BY = -150, -88

-- пиксель клика по доске -> мировые координаты
local function px_to_world(cx, cy)
    local wx = WORLD_X0 + (cx / DW) * (WORLD_X1 - WORLD_X0)
    local wz = WORLD_Z0 + (cy / DH) * (WORLD_Z1 - WORLD_Z0)
    return math.floor(wx + 0.5), math.floor(wz + 0.5)
end

local open_board -- предварительное объявление: on_click ссылается на себя

-- guess = { cx, cy, wx, wz } или nil (ещё не кликали)
open_board = function(guess)
    local nodes = {
        { type = "rect", anchor = "center", x = -160, y = -110, width = 320, height = 240,
          background = "#EE0C0E16" },
        { type = "text", anchor = "center", x = 0, y = -104, align = "center",
          text = "§bКуда это? — отметь место на карте", color = "#FF9AD8FF" },

        -- сама доска: кликабельна (id+on_click)
        { type = "image", anchor = "center", x = BX, y = BY, width = DW, height = DH,
          texture = MAP, id = "board",
          on_click = function(_, click)
              if not click then return end
              local wx, wz = px_to_world(click.x, click.y)
              open_board({ cx = click.x, cy = click.y, wx = wx, wz = wz })
          end },
    }

    if guess then
        -- маркер в точке клика (крестик из двух линий + точка)
        local mx, my = BX + guess.cx, BY + guess.cy
        nodes[#nodes + 1] = { type = "line", anchor = "center",
            x = mx - 6, y = my, x2 = mx + 6, y2 = my, thickness = 1, color = "#FFFFE08A" }
        nodes[#nodes + 1] = { type = "line", anchor = "center",
            x = mx, y = my - 6, x2 = mx, y2 = my + 6, thickness = 1, color = "#FFFFE08A" }
        nodes[#nodes + 1] = { type = "rect", anchor = "center",
            x = mx - 2, y = my - 2, width = 4, height = 4, background = "#FF78E6AA" }

        nodes[#nodes + 1] = { type = "text", anchor = "center", x = 0, y = 98, align = "center",
            text = string.format("§7твоя точка:  §fx %d   z %d", guess.wx, guess.wz),
            color = "#FFCCD4E6" }
        nodes[#nodes + 1] = { type = "button", anchor = "center", x = -50, y = 112,
            width = 100, height = 18, text = "Подтвердить",
            on_click = function()
                lore.report("geo.guess", { x = guess.wx, z = guess.wz })
                lore.log(string.format("geo.guess x=%d z=%d", guess.wx, guess.wz))
            end }
    else
        nodes[#nodes + 1] = { type = "text", anchor = "center", x = 0, y = 98, align = "center",
            text = "§8кликни по карте", color = "#FF6A7A8A" }
    end

    lore.screen({ title = "Карта первого сезона", nodes = nodes })
end

lore.on("geo.open", function()
    open_board(nil)
end)
