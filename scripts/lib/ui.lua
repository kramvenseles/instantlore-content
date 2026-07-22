-- Библиотека виджетов. Прячет ручную раскладку координат за помощниками, которые
-- собирают дерево примитивов. Живёт в контенте (scripts/lib/) — грузится в каждый скрипт
-- как прелюдия, задавая глобальный `ui`, и правится БЕЗ обновления мода. Вся эстетика и
-- раскладка здесь; клиент морозит только геометрию.

ui = {}

local function num(v, d) if v == nil then return d else return v end end

function ui.text(o)
  return { type = "text", anchor = o.anchor or "top_left",
           x = num(o.x, 0), y = num(o.y, 0), text = o.text or "",
           align = o.align or "left", color = o.color or "#FFFFFFFF", height = num(o.height, 10) }
end

function ui.rect(o)
  return { type = "rect", anchor = o.anchor or "top_left",
           x = num(o.x, 0), y = num(o.y, 0), width = num(o.w, 0), height = num(o.h, 0),
           background = o.color or "#FF202030" }
end

-- Кнопка = кликабельный прямоугольник с центрированной подписью. on_click — функция (клик
-- в Lua) либо action — строка (доклад на сервер).
function ui.button(o)
  local w, h = num(o.w, 100), num(o.h, 20)
  return { type = "rect", anchor = o.anchor or "top_left",
           x = num(o.x, 0), y = num(o.y, 0), width = w, height = h,
           background = o.color or "#FF23233A", hover = o.hover or "#FF3A5A88",
           on_click = o.on_click, action = o.action,
           children = { { type = "text", x = math.floor(w / 2), y = math.floor((h - 8) / 2),
                          align = "center", text = o.label or "", color = o.text_color or "#FFFFFFFF" } } }
end

-- Вертикальная раскладка: назначает детям y по высоте предыдущих. Возвращает group.
function ui.column(o)
  local gap = num(o.gap, 4)
  local y = 0
  for _, child in ipairs(o.items) do
    child.x = num(child.x, 0)
    child.y = y
    y = y + num(child.height or child.h, 20) + gap
  end
  return { type = "group", anchor = o.anchor or "top_left",
           x = num(o.x, 0), y = num(o.y, 0), width = num(o.w, 0), height = y, children = o.items }
end

-- Прокручиваемый список: как column, но в scroll-области с клипом и колесом.
function ui.list(o)
  local gap = num(o.gap, 2)
  local y = 0
  for _, child in ipairs(o.items) do
    child.x = num(child.x, 0)
    child.y = y
    y = y + num(child.height or child.h, 22) + gap
  end
  return { type = "scroll", id = o.id or "list", anchor = o.anchor or "center",
           x = o.x, y = o.y, width = o.w, height = o.h,
           background = o.bg or "#66000000", children = o.items }
end

-- Панель с заголовком: возвращает список узлов (фон + шапка + заголовок).
function ui.panel(o)
  local w, h = o.w, o.h
  local hw, hh = math.floor(w / 2), math.floor(h / 2)
  local nodes = { { type = "rect", anchor = "center", x = -hw, y = -hh,
                    width = w, height = h, background = o.bg or "#EE0E0E16" } }
  if o.title then
    nodes[#nodes + 1] = { type = "rect", anchor = "center", x = -hw, y = -hh,
                          width = w, height = 22, background = "#FF1A1A2A" }
    nodes[#nodes + 1] = { type = "text", anchor = "center", x = 0, y = -hh + 7,
                          align = "center", text = o.title, color = "#FFFFD080" }
  end
  return nodes
end

-- Собрать несколько списков узлов в один плоский список.
function ui.merge(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    for _, n in ipairs(list) do out[#out + 1] = n end
  end
  return out
end
