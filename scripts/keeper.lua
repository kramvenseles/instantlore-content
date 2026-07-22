-- ═══════════════════════════════════════════════════════════════════════════
-- «Последний смотритель» — участок лора целиком в контенте.
--
-- Ни строчки серверного кода. Сервер участвует ровно дважды и оба раза сам:
-- рассылает версию контента и, увидев ванильный пакет использования, шлёт
-- item.use. Всё остальное — сцена, счёт вех, разговор, награда — здесь.
--
-- Вышка не привязана к координатам. Скрипт находит её по блокам: наступил на
-- пепел → ищет маяк → вокруг маяка ищет вехи. Автор ставит вышку где угодно,
-- хоть в трёх местах сразу, и переписывать нечего.
-- ═══════════════════════════════════════════════════════════════════════════

local ASH  = "instantlore:block_6"   -- пепел, ковёр вокруг вышки
local WAY  = "instantlore:block_5"   -- веха
local DARK = "instantlore:block_3"   -- погасший маяк

local NEED = 3                        -- вех в цепи

-- ── память между заходами ─────────────────────────────────────────────────
-- ⚠️ Файл игрока, то есть недоверенно. Здесь этим и держим только косметику:
-- какой текст показать пришедшему второй раз. Ценное выдаёт сервер по докладу.

local saved   = lore.load("keeper") or {}
local lit     = saved.lit or {}          -- список ключей "x,y,z" зажжённых вех
local visits  = (saved.visits or 0)
local ended   = saved.ended or false

local function remember()
  lore.save("keeper", { lit = lit, visits = visits, ended = ended })
end

local function key(x, y, z)
  return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z)
end

local function has(k)
  for _, v in ipairs(lit) do if v == k then return true end end
  return false
end

-- ── состояние текущего сеанса ─────────────────────────────────────────────

local shrine  = nil     -- {x,y,z} маяка
local stones  = {}      -- позиции вех вокруг него
local entered = false   -- пролог уже сыграл
local awake   = false   -- маяк разбужен
local hearth  = nil     -- отмена таймера очагов
local finish            -- объявлено заранее: награда вызывает финал

-- ── поиск блоков ──────────────────────────────────────────────────────────
-- Дорого, поэтому оба поиска разовые: пепел ищется дёшево и часто, а вышка
-- и вехи — один раз, когда пепел уже под ногами.

local function look(id, cx, cy, cz, r, up, down, step)
  local found = {}
  step = step or 1
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

-- ── маркеры ───────────────────────────────────────────────────────────────

local function markStone(s)
  local k = key(s.x, s.y, s.z)
  local burning = has(k)

  lore.emit("marker.set", {
    id = "way_" .. k, type = "box", fill = burning,
    x = s.x + 0.5, y = s.y, z = s.z + 0.5, size = 1,
    color = burning and "#FFE07A20" or "#66707088",
  })

  lore.emit("marker.set", {
    id = "waytext_" .. k, type = "text",
    x = s.x + 0.5, y = s.y + 2.6, z = s.z + 0.5, size = 1.1,
    color = burning and "#FFD27A" or "#8A8A96",
    text = burning and "горит" or "холодна",
  })
end

local function markAll()
  for _, s in ipairs(stones) do markStone(s) end
end

-- Цепь: ломаная через все вехи и обратно к маяку. Ровно то, чем эта вышка
-- была при жизни, — звено в линии огней.
local function markChain()
  if not shrine or #stones == 0 then return end

  local pts = {}
  for _, s in ipairs(stones) do
    pts[#pts + 1] = { s.x + 0.5, s.y + 2.2, s.z + 0.5 }
  end
  pts[#pts + 1] = { shrine.x + 0.5, shrine.y + 3.0, shrine.z + 0.5 }
  pts[#pts + 1] = { stones[1].x + 0.5, stones[1].y + 2.2, stones[1].z + 0.5 }

  lore.emit("marker.set", {
    id = "chain", type = "path", points = pts, size = 1.2,
    color = (#lit >= NEED) and "#FFE07A20" or "#55808090",
  })
end

-- ── HUD ───────────────────────────────────────────────────────────────────

local function hud(stage)
  lore.emit("hud.set", { id = "keeper", values = {
    stage = stage, lit = #lit, power = #lit / NEED,
  } })
end

-- ── очаги: горящая веха дышит, а не стоит с одной вспышкой ────────────────

local function startHearth()
  if hearth then return end
  hearth = lore.every(3.0, function()
    for _, s in ipairs(stones) do
      if has(key(s.x, s.y, s.z)) then
        lore.emit("effect.play", { id = "hearth", x = s.x + 0.5, y = s.y, z = s.z + 0.5 })
      end
    end
    if shrine and not awake then
      lore.emit("effect.play", { id = "veil", x = shrine.x + 0.5, y = shrine.y, z = shrine.z + 0.5 })
    end
  end)
end

-- ── пролог ────────────────────────────────────────────────────────────────

local function prologue()
  entered = true
  visits = visits + 1
  remember()

  stones = look(WAY, shrine.x, shrine.y, shrine.z, 12, 3, 3)

  lore.log(string.format("вышка на %d %d %d, вех найдено %d, зажжено %d",
    shrine.x, shrine.y, shrine.z, #stones, #lit))

  lore.emit("hud.show", { id = "keeper", values = {
    stage = (visits > 1) and "Ты уже был здесь" or "Пепелище",
    lit = #lit, power = #lit / NEED,
  } })

  -- Граница пепелища: круг у земли. Второй тип маркера в той же сцене, что
  -- и ломаная, — чтобы видно было, что это разные фигуры, а не одна.
  lore.emit("marker.set", {
    id = "edge", type = "circle",
    x = shrine.x + 0.5, y = shrine.y + 0.05, z = shrine.z + 0.5,
    radius = 11.0, size = 0.8, color = "#66A8A0B4",
  })

  markAll()
  markChain()
  startHearth()

  lore.emit("music.play", { id = "minecraft:music_disc.far", replace = true })

  if visits > 1 then
    -- Память с прошлого захода: текст другой, и это единственное, на что она
    -- влияет. Проверить её честно можно только выйдя и зайдя снова.
    lore.emit("title.show", {
      title = "§8Ты возвращался сюда",
      subtitle = "§7заход " .. visits .. ", вех зажжено " .. #lit .. " из " .. NEED,
      fade_in = 10, stay = 60, fade_out = 20,
    })
  else
    lore.emit("cutscene.play", { id = "arrival" })
  end

  -- Шелестни: если они рядом, сцена это замечает. Чтение мира ради реплики,
  -- а не ради механики.
  lore.after(2.0, function()
    local near = lore.entities(20)
    local n = 0
    for _, e in ipairs(near) do
      if string.find(e.type, "lore_object") or string.find(e.type, "lore_mob") then n = n + 1 end
    end
    if n > 0 then
      lore.emit("actionbar.set", { text = "§8Что-то ещё шевелится в пепле (" .. n .. ")" })
    end
  end)
end

-- ── зажечь веху ───────────────────────────────────────────────────────────

local function light(bx, by, bz)
  local k = key(bx, by, bz)
  if has(k) then
    lore.emit("actionbar.set", { text = "§7Эта веха уже горит" })
    return
  end

  lit[#lit + 1] = k
  remember()

  lore.emit("effect.play", { id = "spark", x = bx + 0.5, y = by, z = bz + 0.5 })
  markStone({ x = bx, y = by, z = bz })
  markChain()
  startHearth()

  if #lit < NEED then
    hud("Вехи разгораются")
    lore.emit("actionbar.set", {
      text = "§6Веха приняла искру §7— осталось " .. (NEED - #lit),
    })
  else
    hud("Цепь замкнулась")
    lore.emit("title.show", {
      title = "§6Цепь замкнулась", subtitle = "§7Маяк ждёт",
      fade_in = 10, stay = 50, fade_out = 15,
    })
    lore.emit("toast.show", {
      title = "§eТри огня", description = "Теперь маяк примет искру",
    })
    lore.emit("sound.play", { id = "minecraft:block.bell.resonate", volume = 1.0, pitch = 0.7 })
  end
end

-- ── награда: экран собран из ui.lua, клик обрабатывается здесь же ─────────
-- Выдаёт награду не он: экран только спрашивает и докладывает. Ценное живёт
-- на сервере, потому что этот экран — на машине игрока.

local function rewards(answer)
  local chosen = nil
  local render

  local function card(y, id, label, note, item)
    return {
      { type = "rect", anchor = "center", x = -128, y = y, width = 256, height = 30,
        background = (chosen == id) and "#FF2E2418" or "#FF191922",
        hover = "#FF3A3048", on_click = function() chosen = id; render() end,
        children = {
          { type = "item", x = 8, y = 7, item = item, count = 1 },
          { type = "text", x = 32, y = 6, text = label, color = "#FFE8DCC0" },
          { type = "text", x = 32, y = 18, text = "§7" .. note, color = "#FF8A8496" },
        } },
    }
  end

  render = function()
    local nodes = ui.merge(
      ui.panel { w = 280, h = 210, title = "§6Смотритель протягивает руку" },
      { { type = "text", anchor = "center", x = 0, y = -78, align = "center",
          text = "§7" .. answer, color = "#FF9A93A8" } },
      card(-62, "ember",  "Уголёк",            "часть огня, что ты вернул",  "instantlore:item_3"),
      card(-28, "seal",   "Печать смотрителя", "знак того, кто стоял до конца", "instantlore:item_4"),
      card(6,   "nothing","Ничего",            "оставить всё как есть",      "minecraft:air"),
      {
        ui.button { anchor = "center", x = -60, y = 52, w = 120, h = 22, label = "Принять",
          color = "#FF2A4A2A", hover = "#FF3A6A3A",
          on_click = function()
            if not chosen then
              lore.emit("actionbar.set", { text = "§7Сначала выбери" })
              return
            end
            -- Доклад наверх: сервер решит, выдавать ли. Клиент лишь просит.
            lore.report("keeper.reward", { choice = chosen, answer = answer, visits = visits })
            lore.emit("toast.show", { title = "§eПросьба услышана", description = "Смотритель кивнул" })
            lore.emit("effect.play", { id = "seal" })
            ended = true
            remember()
            finish()
          end },
        ui.text { anchor = "center", x = 0, y = 80, align = "center",
          text = "§8Esc — уйти молча", color = "#FF6A6478" },
      })

    lore.screen { title = "Дар", nodes = nodes }
  end

  render()
end

-- ── финал ─────────────────────────────────────────────────────────────────

finish = function()
  lore.emit("bossbar.hide", { id = "keeper" })
  lore.emit("hud.hide", { id = "keeper" })
  lore.emit("marker.clear", {})
  lore.emit("music.stop", {})
  lore.emit("title.show", {
    title = "§6Огонь передан", subtitle = "§7Глава I окончена",
    fade_in = 10, stay = 70, fade_out = 25,
  })
  hud("Окончено")
end

local function awaken()
  if awake then return end
  awake = true

  local cx, cy, cz = shrine.x + 0.5, shrine.y, shrine.z + 0.5

  -- Игрока держим: он смотрит на маяк, пока тот просыпается. Потолок обязателен —
  -- иначе застрявший захват оставит игрока без управления навсегда.
  lore.emit("player.control", { lock_move = true, timeout = 12 })
  lore.emit("player.look", { x = cx, y = cy + 4, z = cz, turn = 60 })

  lore.emit("effect.play", { id = "waking", x = cx, y = cy, z = cz })
  lore.emit("bossbar.show", {
    id = "keeper", title = "§6Маяк просыпается",
    percent = 0.0, color = "yellow", style = "notched_10",
  })

  local p = 0.0
  local stop
  stop = lore.every(0.35, function()
    p = p + 0.05
    lore.emit("bossbar.set", { id = "keeper", percent = math.min(p, 1.0) })
    if p >= 1.0 then
      stop()
      lore.emit("bossbar.set", { id = "keeper", title = "§eСмотритель пробуждён" })
      lore.emit("player.release", {})
      lore.emit("sound.play", { id = "minecraft:block.beacon.power_select", volume = 1.0, pitch = 0.5 })

      -- Луч от маяка вверх — цепь снова передаёт огонь дальше.
      lore.emit("marker.set", {
        id = "beam", type = "line", size = 2.0, color = "#FFFFC24A",
        x = cx, y = cy + 3.2, z = cz, x2 = cx, y2 = cy + 40, z2 = cz,
      })

      local me = lore.player()
      lore.after(1.5, function()
        lore.emit("dialog.show", {
          id = "keeper", values = { player = me and me.name or "странник" },
        })
      end)
    end
  end)

  hud("Пробуждение")
end

-- ── ввод игрока ───────────────────────────────────────────────────────────

lore.on("item.use", function(data)
  if data.name == "keeper_seal" then
    local p = lore.player()
    if p then lore.emit("effect.play", { id = "seal", x = p.x, y = p.y, z = p.z }) end
    lore.emit("title.show", {
      title = "§6Печать тёплая", subtitle = "§7заходов на вышку: " .. visits,
      fade_in = 5, stay = 45, fade_out = 15,
    })
    return
  end

  if data.name ~= "lantern" then return end

  if data.x == nil then
    lore.log("фонарь: применён по воздуху, блока нет")
    lore.emit("actionbar.set", { text = "§8Наведись на веху" })
    return
  end

  local b = lore.block(data.x, data.y, data.z)
  lore.log(string.format("фонарь: %s,%s,%s → %s",
    tostring(data.x), tostring(data.y), tostring(data.z), tostring(b and b.id)))
  if not b then return end

  if b.id == WAY then
    light(data.x, data.y, data.z)
  elseif b.id == DARK then
    if #lit >= NEED then
      shrine = { x = data.x, y = data.y, z = data.z }
      awaken()
    else
      lore.emit("actionbar.set", {
        text = "§8Маяк холоден. Вех зажжено " .. #lit .. " из " .. NEED,
      })
      lore.emit("sound.play", { id = "minecraft:block.stone.hit", volume = 0.8, pitch = 0.6 })
    end
  else
    lore.emit("actionbar.set", { text = "§8Фонарь не отзывается" })
  end
end)

-- Ответ в диалоге. До 0.40.0 этого события на клиентской шине не было вовсе:
-- выбор уходил только на сервер, и разговор нельзя было довести без Java.
lore.on("dialog.choice", function(data)
  if data.id ~= "keeper" then return end

  local said = ({
    duty  = "«Огонь должен гореть.»",
    ask   = "«Кто оборвал цепь?»",
    greed = "«Я пришёл за тем, что ты стережёшь.»",
  })[data.key] or "«...»"

  local reply = ({
    duty  = "Смотритель молчит дольше, чем нужно. Потом кивает.",
    ask   = "«Никто. Просто некому стало передавать.»",
    greed = "«Честно. Это редкость.»",
  })[data.key] or ""

  lore.emit("actionbar.set", { text = "§7" .. reply })
  lore.emit("sound.play", { id = "minecraft:block.beacon.ambient", volume = 0.8, pitch = 0.6 })
  lore.after(1.2, function() rewards(said) end)
end)

lore.on("dialog.cancelled", function()
  lore.emit("actionbar.set", { text = "§8Смотритель ждёт. Он умеет ждать" })
end)

-- ── дозор: пепел под ногами включает сцену ────────────────────────────────
-- Дёшево нарочно: шаг 3 по решётке. Пепелище широкое, промахнуться нельзя,
-- а полный перебор радиуса 9 стоил бы вчетверо дороже каждую секунду.

lore.every(1.0, function()
  if entered then return end

  local p = lore.player()
  if not p then return end

  local px, py, pz = math.floor(p.x), math.floor(p.y), math.floor(p.z)

  local ash = look(ASH, px, py, pz, 9, 0, 1, 3)
  if #ash == 0 then return end

  local found = look(DARK, px, py, pz, 14, 2, 3)
  if #found == 0 then
    lore.log("пепел есть, маяка рядом нет — сцена не начата")
    return
  end

  shrine = found[1]
  prologue()
end)

lore.log("«Последний смотритель» загружен: заходов " .. visits .. ", вех зажжено " .. #lit)
