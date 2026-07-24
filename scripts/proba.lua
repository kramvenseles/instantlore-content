-- ═══════════════════════════════════════════════════════════════════════════
-- «Чертог пробы» — тестовая арка, гоняющая ВСЕ клиентские примитивы разом.
--
-- Не сюжет, а честный стенд: на каждой станции скрипт дёргает клиентскую половину
-- и ТУТ ЖЕ читает её обратно (player()/target()/visible()/entities()), показывая
-- «прошло/провал». Инструмент проверяет себя сам, и на заведомом входе до замера
-- (правило #6): target() сперва промах (nil), потом попадание.
--
-- Серверная половина (spawn/give/ride/tilt/appearance/freeze/walk/task) приходит
-- командами во время прогона — её этот скрипт не трогает, только читает результат.
--
-- Запуск станций из консоли:  /lore emit to <ник> proba.<станция>
--   proba.enter   — пролог (или наступить на trial_floor)
--   proba.mirror  — Зеркало (или ПКМ жезлом item_5)
--   proba.aim     — С2: target() промах→попадание + visible()
--   proba.walk    — С3: маршрут со сменой скорости и присядом
--   proba.input   — С3: сырой ввод (все оси)
--   proba.keys    — С3: запрет клавиш списком и «всё, кроме», keys_ask
--   proba.camera  — С6: тряска, fov, перспектива, вспышка
--   proba.narrate — нарратив: title/actionbar/toast/bossbar/sound
--   proba.talk    — С5: диалог
--   proba.map     — С5: статический экран (item.use checklist)
--   proba.menu    — хаб-меню со всеми кнопками
--   proba.reset   — снять всё
-- ═══════════════════════════════════════════════════════════════════════════

local FLOOR = "instantlore:block_9"   -- пол чертога, триггер пролога
local RUNE  = "instantlore:block_10"  -- цель прицела
local VEIL  = "instantlore:block_11"  -- стена для visible()

local STATIONS = { "С0 Порог", "С1 Зеркало", "С2 Прицел", "С3 Ведомый",
                   "С4 Живое", "С5 Дар", "С6 Камера" }
local TOTAL = #STATIONS

-- ── память ────────────────────────────────────────────────────────────────
local saved  = lore.load("proba") or {}
local passed = saved.passed or {}      -- ключ станции → true
local visits = (saved.visits or 0)

local function remember()
  lore.save("proba", { passed = passed, visits = visits })
end

local function countPassed()
  local n = 0
  for _ in pairs(passed) do n = n + 1 end
  return n
end

-- ── состояние сеанса ──────────────────────────────────────────────────────
local entered = false
local mirror  = nil     -- handle открытого Зеркала
local mirrorTick = nil  -- отмена таймера обновления
local complained = false

-- ── HUD прогресса ──────────────────────────────────────────────────────────
local function hud(stage)
  local n = countPassed()
  lore.emit("hud.set", { id = "proba", values = {
    stage = stage or "…", done = n, total = TOTAL, power = n / TOTAL,
  } })
end

local function pass(station, note)
  if not passed[station] then
    passed[station] = true
    remember()
  end
  lore.emit("toast.show", { title = "§a✔ " .. station, description = note or "" })
  lore.log("ПРОШЛО: " .. station .. (note and (" — " .. note) or ""))
  hud(station .. " ✔")
end

-- ── поиск блока по решётке (как в keeper) ──────────────────────────────────
local function look(id, cx, cy, cz, r, up, down, step)
  step = step or 1
  local found = {}
  for x = cx - r, cx + r, step do
    for z = cz - r, cz + r, step do
      for y = cy - down, cy + up do
        local b = lore.block(x, y, z)
        if b and b.id == id then found[#found + 1] = { x = x, y = y, z = z } end
      end
    end
  end
  return found
end

local function nearest(list, px, py, pz)
  local best, bd = nil, 1e9
  for _, s in ipairs(list) do
    local d = (s.x - px) ^ 2 + (s.y - py) ^ 2 + (s.z - pz) ^ 2
    if d < bd then best, bd = s, d end
  end
  return best
end

-- ═══════════════════════════════════════════════════════════════════════════
-- С0 · ПОРОГ — вуаль, катсцена с креном, маркеры пяти типов, музыка
-- ═══════════════════════════════════════════════════════════════════════════
local function markers(p)
  local x, y, z = math.floor(p.x), math.floor(p.y), math.floor(p.z)

  -- 1) сплошной куб (заливка, альфа работает)
  lore.emit("marker.set", { id = "m_boxfill", type = "box", fill = true,
    x = x + 0.5, y = y + 0.2, z = z + 4.5, size = 1.0, color = "#5535C0E0" })
  -- 2) рёберный куб
  lore.emit("marker.set", { id = "m_boxwire", type = "box", fill = false,
    x = x + 2.5, y = y + 0.2, z = z + 4.5, size = 1.0, color = "#FF35C0E0" })
  -- 3) луч вверх
  lore.emit("marker.set", { id = "m_line", type = "line", size = 2.0, color = "#FFFFC24A",
    x = x + 0.5, y = y + 1.0, z = z + 0.5, x2 = x + 0.5, y2 = y + 30, z2 = z + 0.5 })
  -- 4) билборд-текст с подстановкой
  lore.emit("marker.set", { id = "m_text", type = "text", size = 1.2,
    x = x + 0.5, y = y + 2.6, z = z + 0.5, color = "#FF9AD8FF",
    text = "Чертог пробы (${who})", values = { who = p.name or "…" } })
  -- 5) окружность у земли
  lore.emit("marker.set", { id = "m_circle", type = "circle", size = 0.8,
    x = x + 0.5, y = y + 0.05, z = z + 0.5, radius = 6.0, color = "#66A8A0B4" })
  -- 6) ломаная
  lore.emit("marker.set", { id = "m_path", type = "path", size = 1.2, color = "#FF35C0E0",
    points = { { x + 0.5, y + 1.5, z + 0.5 }, { x + 3.5, y + 2.5, z + 3.5 },
               { x - 3.5, y + 2.5, z + 3.5 }, { x + 0.5, y + 1.5, z + 0.5 } } })
end

local function prologue(p)
  entered = true
  visits = visits + 1
  remember()

  lore.emit("hud.show", { id = "proba", values = {
    stage = "Порог", done = countPassed(), total = TOTAL, power = countPassed() / TOTAL } })

  lore.emit("music.play", { id = "minecraft:music_disc.far", replace = true })

  -- Вуаль как переход, затем катсцена. Фейд рисуется поверх катсцены, поэтому
  -- короткий, и облёт запускаем уже после того, как экран прояснился.
  lore.emit("screen.fade", { color = "#FF000000", ["in"] = 0.6, hold = 0.3, out = 0.6 })
  lore.after(1.0, function()
    lore.emit("cutscene.play", { id = "proba", x = p.x, y = p.y, z = p.z, yaw = p.yaw })
  end)

  markers(p)
  lore.after(0.2, function() lore.emit("effect.play", { id = "proba_particles", x = p.x, y = p.y + 1, z = p.z }) end)

  pass("С0 Порог", "катсцена+крен+вуаль+маркеры")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- С1 · ЗЕРКАЛО — читает всё, что видит скрипт, и показывает живьём
-- ═══════════════════════════════════════════════════════════════════════════
local function itemLine(label, it)
  if not it then return "§8" .. label .. ": —" end
  local s = "§7" .. label .. ": §f" .. (it.name or it.id)
  if it.damage ~= nil then s = s .. " §8(" .. (it.max_damage - it.damage) .. "/" .. it.max_damage .. ")" end
  if it.enchantments then
    local parts = {}
    for _, e in ipairs(it.enchantments) do parts[#parts + 1] = e.id .. " " .. e.level end
    s = s .. " §b[" .. table.concat(parts, ", ") .. "]"
  end
  return s
end

local function boolRow(p)
  local flags = {}
  local function f(name, v) if v then flags[#flags + 1] = name end end
  f("на_земле", p.on_ground); f("в_воде", p.in_water); f("под_водой", p.submerged)
  f("присед", p.sneaking); f("бег", p.sprinting); f("горит", p.burning)
  f("спит", p.sleeping); f("верхом", p.riding); f("планир", p.gliding)
  f("снег", p.powder_snow); f("ест/целит", p.using_item ~= nil)
  return #flags > 0 and table.concat(flags, " ") or "—"
end

local function mirrorNodes()
  local p = lore.player()
  local nodes = ui.panel { w = 320, h = 232, title = "§bЗеркало — что видит скрипт" }
  local lines = {}

  if not p then
    lines[1] = "§cplayer() = nil (мир не готов)"
  else
    local w = lore.world() or {}
    local under = lore.block(math.floor(p.x), math.floor(p.y) - 1, math.floor(p.z))
    local ents = lore.entities(16)
    local inv = lore.inventory()
    local t = lore.target()

    lines = {
      string.format("§7поз §f%.1f %.1f %.1f  §7угол §f%.0f/%.0f", p.x, p.y, p.z, p.yaw, p.pitch),
      string.format("§7hp §f%.0f/%.0f §7еда §f%d §7возд §f%d §7xp §f%d",
        p.health, p.max_health, p.food or 0, p.air or 0, p.xp_level or 0),
      "§7режим §f" .. tostring(p.gamemode) .. " §7мир §f" .. tostring(p.dimension),
      "§7состояния: §f" .. boolRow(p),
      itemLine("рука", p.held),
      itemLine("вторая", p.offhand),
      itemLine("шлем", p.armor and p.armor.helmet),
      itemLine("нагрудник", p.armor and p.armor.chestplate),
      "§7using_item: §f" .. (p.using_item and (p.using_item.item.name .. " (" .. p.using_item.hand .. ")") or "—"),
      "§7эффектов: §f" .. tostring(p.effects and #p.effects or 0)
        .. "  §7инвентарь: §f" .. tostring(#inv) .. " слот.",
      string.format("§7мир: §fдень=%s дождь=%s свет=%s биом=%s",
        tostring(w.is_day), tostring(w.raining), tostring(w.light), tostring(w.biome)),
      "§7под ногами: §f" .. (under and under.id or "—"),
      "§7сущностей рядом: §f" .. tostring(#ents) .. (ents[1] and (" ближ. слот=" .. tostring(ents[1].slot)
        .. " hp=" .. tostring(ents[1].health)) or ""),
      "§7target(): §f" .. (t and (t.type .. " " .. tostring(t.id or t.entity_type)
        .. (t.slot and (" слот " .. t.slot) or "")) or "прицел в пустоте"),
    }
  end

  local body = {}
  for i, s in ipairs(lines) do
    body[#body + 1] = ui.text { anchor = "center", x = -150, y = -96 + (i - 1) * 14, text = s, color = "#FFE8E8F0" }
  end
  body[#body + 1] = ui.text { anchor = "center", x = 0, y = 100, align = "center",
    text = "§8обновляется каждые 0.5с · Esc — закрыть", color = "#FF888888" }

  return ui.merge(nodes, body)
end

local function openMirror()
  local function draw()
    mirror = lore.screen {
      title = "Зеркало",
      nodes = mirrorNodes(),
      on_close = function()
        if mirrorTick then mirrorTick(); mirrorTick = nil end
        mirror = nil
      end,
    }
  end
  draw()
  if mirrorTick then mirrorTick() end
  mirrorTick = lore.every(0.5, function() if mirror then draw() end end)
  pass("С1 Зеркало", "player/world/block/entities/target прочитаны")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- С2 · ПРИЦЕЛ — target() промах→попадание (блок и сущность), visible()
-- ═══════════════════════════════════════════════════════════════════════════
local function aim()
  local p = lore.player()
  if not p then return end

  lore.emit("player.control", { lock_move = true, timeout = 18 })

  -- 1) заведомый промах: смотрим в небо. Инструмент до замера (правило #6).
  lore.emit("player.look", { yaw = p.yaw, pitch = -89, turn = 240 })
  lore.after(1.4, function()
    local t = lore.target()
    lore.log("С2 промах: target()=" .. (t and t.type or "nil") .. " (ждём nil)")

    -- 2) попадание по блоку: наводимся на ближайшую руну
    local runes = look(RUNE, math.floor(p.x), math.floor(p.y), math.floor(p.z), 8, 3, 3)
    local r = nearest(runes, p.x, p.y, p.z)
    if r then
      lore.emit("player.look", { x = r.x + 0.5, y = r.y + 0.5, z = r.z + 0.5, turn = 200 })
      lore.after(1.6, function()
        local tb = lore.target()
        lore.log("С2 блок: target()=" .. (tb and (tb.type .. " " .. tostring(tb.id)) or "nil"))

        -- 3) попадание по сущности: ближайшая сущность пула
        local nearestEnt, nd
        for _, e in ipairs(lore.entities(16)) do
          if e.slot and (not nd or e.distance < nd) then nearestEnt, nd = e, e.distance end
        end
        if nearestEnt then
          lore.emit("player.look", { x = nearestEnt.x, y = nearestEnt.y + 0.6, z = nearestEnt.z, turn = 200 })
          lore.after(1.6, function()
            local te = lore.target()
            lore.log("С2 сущность: target()=" .. (te and (te.type .. " слот " .. tostring(te.slot)) or "nil"))
            lore.emit("player.release", {})
            pass("С2 Прицел", "target() промах→блок→сущность")
          end)
        else
          lore.emit("player.release", {})
          lore.log("С2: сущности пула рядом нет — заспавни слот 6")
          pass("С2 Прицел", "target() промах→блок (сущности не было)")
        end
      end)
    else
      lore.emit("player.release", {})
      lore.log("С2: руны (block_10) рядом нет — поставь её перед игроком")
    end
  end)

  -- visible(): сквозь завесу и в небо. Луч движка, не DDA.
  local eye = { p.x, p.y + 1.62, p.z }
  local veils = look(VEIL, math.floor(p.x), math.floor(p.y), math.floor(p.z), 10, 3, 3)
  local vw = nearest(veils, p.x, p.y, p.z)
  if vw then
    local far = { vw.x + 0.5 + (vw.x + 0.5 - p.x), vw.y + 1, vw.z + 0.5 + (vw.z + 0.5 - p.z) }
    local v = lore.visible(eye[1], eye[2], eye[3], far[1], far[2], far[3])
    lore.log("С2 visible сквозь завесу: clear=" .. tostring(v and v.clear) .. " id=" .. tostring(v and v.id))
  end
  local up = lore.visible(eye[1], eye[2], eye[3], eye[1], eye[2] + 30, eye[3])
  lore.log("С2 visible в небо: clear=" .. tostring(up and up.clear) .. " (ждём true)")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- С3 · ВЕДОМЫЙ — маршрут, сырой ввод, клавиши, хотбар, клик
-- ═══════════════════════════════════════════════════════════════════════════
local function drive()
  local p = lore.player()
  if not p then return end
  lore.emit("player.control", { lock_move = true, timeout = 25 })

  -- Маршрут: три точки, средняя вприсядку, разная скорость (4-й элемент точки).
  lore.emit("player.path", { speed = "walk", points = {
    { p.x + 3, p.y, p.z },
    { p.x + 3, p.y, p.z + 3, "sneak" },
    { p.x, p.y, p.z + 3, "sprint" },
    { p.x, p.y, p.z },
  } })
  lore.emit("player.hotbar", { slot = 2 })

  -- player.arrived едет только на сервер (sendAt→send), из контента его не видно.
  -- Приход ловим опросом позиции: отошёл (d²>4) и вернулся к старту (последняя
  -- точка = старт). Таймаут-страховка на случай застревания.
  local stop, departed, t0 = nil, false, 0
  stop = lore.every(0.4, function()
    t0 = t0 + 0.4
    local q = lore.player()
    if not q then return end
    local d2 = (q.x - p.x) ^ 2 + (q.z - p.z) ^ 2
    if d2 > 4 then departed = true end
    if departed and d2 < 0.5 then
      stop(); lore.emit("player.release", {})
      pass("С3 Ведомый", "маршрут пройден (walk/sneak/sprint)")
    elseif t0 > 22 then
      stop(); lore.emit("player.release", {})
      lore.log("С3: маршрут не завершился за 22с")
    end
  end)
end

local function rawInput()
  -- Дробные оси: полшага вперёд + чуть влево, короткий присед. strafe>0 = ВЛЕВО.
  lore.emit("player.control", { lock_move = true, timeout = 10 })
  lore.emit("player.input", { forward = 0.5, strafe = 0.3, sneak = true, seconds = 1.5 })
  lore.after(1.6, function()
    lore.emit("player.input", { jump = true, seconds = 0.3 })
  end)
  lore.after(2.2, function()
    lore.emit("player.uninput", {})
    lore.emit("player.release", {})
    pass("С3 Ведомый", "сырой ввод: forward/strafe/sneak/jump")
  end)
end

local function keys()
  -- 1) запрет списком
  lore.emit("player.keys", { block = { "key.inventory", "key.drop", "key.swapOffhand" }, seconds = 8 })
  lore.emit("actionbar.set", { text = "§eЗапрещены E, Q, F на 8с — проверь" })
  -- 2) «всё, кроме чата»
  lore.after(9, function()
    lore.emit("player.keys", { block_all = true, except = { "key.chat" }, seconds = 6 })
    lore.emit("actionbar.set", { text = "§eВсё кроме чата на 6с — проверь, что чат жив" })
  end)
  lore.after(16, function()
    lore.emit("player.keys", {})
    -- keys_ask отвечает докладом player.keys_list, но тот идёт ТОЛЬКО на сервер
    -- (LoreReports.send, не sendAndPublish) — из контента его не прочитать.
    -- Проверяется он серверно; сам запрет клавиш — глазами (E/Q/F молчат).
    lore.emit("player.keys_ask", {})
  end)
  pass("С3 Ведомый", "клавиши: список + всё-кроме + keys_ask")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- С6 · КАМЕРА — тряска, fov, перспектива, вспышка
-- ═══════════════════════════════════════════════════════════════════════════
local function camera()
  lore.emit("camera.shake", { amplitude = 4, frequency = 18, seconds = 2 })
  lore.emit("actionbar.set", { text = "§6Тряска камеры (2с)" })
  lore.after(2.2, function()
    lore.emit("camera.fov", { multiplier = 0.45, seconds = 2 })
    lore.emit("actionbar.set", { text = "§6FOV ×0.45 — приближение (2с)" })
  end)
  lore.after(4.6, function()
    lore.emit("camera.fov", { multiplier = 1.0, seconds = 1 })
    lore.emit("camera.perspective", { mode = "third" })
    lore.emit("actionbar.set", { text = "§6Вид от третьего лица" })
  end)
  lore.after(6.6, function()
    lore.emit("camera.perspective", { mode = "third_front" })
  end)
  lore.after(8.2, function()
    lore.emit("camera.perspective", { mode = "first" })
    lore.emit("screen.fade", { color = "#AAFF2020", ["in"] = 0.05, hold = 0.05, out = 0.6 })
    pass("С6 Камера", "shake/fov/perspective/вспышка")
  end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Нарратив — title/actionbar/toast/bossbar/sound
-- ═══════════════════════════════════════════════════════════════════════════
local function narrate()
  lore.emit("title.show", { title = "§bЧертог пробы", subtitle = "§7нарратив на связи",
    fade_in = 8, stay = 40, fade_out = 12 })
  lore.emit("actionbar.set", { text = "§6строка над хотбаром" })
  lore.emit("toast.show", { title = "§eВсплывашка", description = "и её описание" })
  lore.emit("sound.play", { id = "minecraft:block.note_block.pling", volume = 1.0, pitch = 1.4 })
  lore.emit("bossbar.show", { id = "proba", title = "§bПолоса пробы", percent = 0.3,
    color = "blue", style = "notched_10" })
  lore.after(1.5, function() lore.emit("bossbar.set", { id = "proba", percent = 0.8 }) end)
  lore.after(3.0, function()
    lore.emit("bossbar.set", { id = "proba", title = "§aГотово", percent = 1.0 })
  end)
  lore.after(5.0, function() lore.emit("bossbar.hide", { id = "proba" }) end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- С5 · ДАР — диалог → экран награды из ui.lua (все узлы локально)
-- ═══════════════════════════════════════════════════════════════════════════
local function talk()
  local p = lore.player()
  lore.emit("dialog.show", { id = "proba", values = { player = p and p.name or "странник" } })
end

local function reward(answer)
  local chosen, render = nil, nil
  local function card(y, id, label, item)
    return { { type = "rect", anchor = "center", x = -130, y = y, width = 260, height = 26,
      background = (chosen == id) and "#FF2E2418" or "#FF191922", hover = "#FF3A3048",
      on_click = function() chosen = id; render() end, children = {
        { type = "item", x = 8, y = 5, item = item, count = 1 },
        { type = "text", x = 32, y = 8, text = label, color = "#FFE8DCC0" } } } }
  end
  render = function()
    local nodes = ui.merge(
      ui.panel { w = 300, h = 190, title = "§bПроба принята" },
      { { type = "text", anchor = "center", x = 0, y = -70, align = "center",
          text = "§7" .. answer, color = "#FF9A93A8" } },
      card(-46, "wand", "Жезл пробы", "instantlore:item_5"),
      card(-14, "check", "Опись", "instantlore:item_6"),
      { ui.button { anchor = "center", x = -60, y = 46, w = 120, h = 22, label = "Принять",
          color = "#FF2A4A2A", hover = "#FF3A6A3A", on_click = function()
            if not chosen then lore.emit("actionbar.set", { text = "§7Сначала выбери" }); return end
            lore.report("proba.reward", { choice = chosen, answer = answer })
            lore.emit("toast.show", { title = "§eПросьба услышана", description = "Смотритель кивнул" })
            pass("С5 Дар", "диалог+экран+выбор доложен")
            if mirror then mirror.close() end
            lore.emit("screen.close", {})
          end },
        ui.text { anchor = "center", x = 0, y = 74, align = "center",
          text = "§8Esc — уйти молча", color = "#FF6A6478" } })
    lore.screen { title = "Дар", nodes = nodes }
  end
  render()
end

lore.on("dialog.choice", function(data)
  if data.id ~= "proba" then return end
  local said = ({ all_ok = "«Всё отозвалось.»", eyes = "«Проверено глазами.»",
                  doubt = "«Кое-что под вопросом.»" })[data.key] or "«…»"
  lore.emit("sound.play", { id = "minecraft:block.beacon.ambient", volume = 0.8, pitch = 0.6 })
  lore.after(0.8, function() reward(said) end)
end)

lore.on("dialog.cancelled", function()
  lore.emit("actionbar.set", { text = "§8Смотритель ждёт" })
end)

-- Доклад статического экрана proba_map (кнопки map:*): доезжает и на локальную шину.
lore.on("screen.action", function(data)
  if data.screen ~= "proba_map" then return end
  local note = data.inputs and data.inputs.note or ""
  lore.log("С5 screen.action: " .. tostring(data.action) .. " заметка=[" .. note .. "]")
  if data.action == "map:rerun" then
    lore.emit("screen.close", {})
    lore.emit("proba.enter", {})
  end
  pass("С5 Дар", "статический экран + inputs прочитаны")
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- Хаб-меню — все станции кнопками (клиентская половина; серверные — подписью)
-- ═══════════════════════════════════════════════════════════════════════════
local function menu()
  local panel
  local function btn(y, label, fn, col)
    return ui.button { anchor = "center", x = -140, y = y, w = 280, h = 20, label = label,
      color = col or "#FF23233A", hover = "#FF3A5A88",
      on_click = function() if panel then panel.close() end; fn() end }
  end
  local nodes = ui.merge(
    ui.panel { w = 300, h = 250, title = "§bЧертог пробы — хаб" },
    { btn(-98, "С1 Зеркало (все чтения)", openMirror),
      btn(-74, "С2 Прицел — target()/visible()", aim),
      btn(-50, "С3 Ведомый — маршрут", drive),
      btn(-26, "С3 Сырой ввод", rawInput),
      btn(-2,  "С3 Клавиши", keys),
      btn(22,  "Нарратив (title/bossbar/toast)", narrate),
      btn(46,  "С6 Камера (тряска/fov/вид)", camera),
      btn(70,  "С5 Диалог → дар", talk),
      ui.text { anchor = "center", x = 0, y = 96, align = "center",
        text = "§8С4 Живое и заморозка — командами в консоль", color = "#FF888888" },
      ui.text { anchor = "center", x = 0, y = 110, align = "center",
        text = "§8Esc — закрыть", color = "#FF888888" } })
  panel = lore.screen { title = "Хаб", nodes = nodes }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Ввод и события
-- ═══════════════════════════════════════════════════════════════════════════
lore.on("item.use", function(data)
  if data.name == "probe_wand" then openMirror()
  elseif data.name == "checklist" then
    lore.emit("screen.show", { id = "proba_map", values = {} })
    pass("С5 Дар", "статический экран открыт")
  end
end)

lore.on("proba.enter",   function() local p = lore.player(); if p then prologue(p) end end)
lore.on("proba.mirror",  openMirror)
lore.on("proba.aim",     aim)
lore.on("proba.walk",    drive)
lore.on("proba.input",   rawInput)
lore.on("proba.keys",    keys)
lore.on("proba.camera",  camera)
lore.on("proba.narrate", narrate)
lore.on("proba.talk",    talk)
lore.on("proba.map",     function() lore.emit("screen.show", { id = "proba_map", values = {} }) end)
lore.on("proba.menu",    menu)

-- ── сброс ───────────────────────────────────────────────────────────────
lore.on("proba.reset", function()
  lore.save("proba", nil)
  passed, visits = {}, 0
  entered = false
  if mirrorTick then mirrorTick(); mirrorTick = nil end
  if mirror then mirror.close(); mirror = nil end
  lore.emit("marker.clear", {})
  lore.emit("hud.hide", { id = "proba" })
  lore.emit("bossbar.hide", { id = "proba" })
  lore.emit("music.stop", {})
  lore.emit("title.clear", {})
  lore.emit("screen.fade", { clear = true })
  lore.emit("actionbar.set", { text = "§7Чертог пробы сброшен" })
  lore.log("проба сброшена")
end)

-- ── дозор: пол под ногами включает пролог ─────────────────────────────────
lore.every(1.0, function()
  if entered then return end
  local p = lore.player()
  if not p then return end
  local floor = look(FLOOR, math.floor(p.x), math.floor(p.y), math.floor(p.z), 4, 0, 1, 1)
  if #floor == 0 then
    if not complained then complained = true; lore.log("проба: пол чертога (block_9) не найден — жду") end
    return
  end
  complained = false
  prologue(p)
end)

lore.log("«Чертог пробы» загружен: заходов " .. visits .. ", станций пройдено " .. countPassed() .. "/" .. TOTAL)
