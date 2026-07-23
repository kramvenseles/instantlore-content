-- Полигон 0.46.0. Собирает четыре примитива, добавленных и НЕ проверенных живьём:
-- крен катсцены, экранный фейд, луч видимости и (командой) верховую езду. Живёт в
-- контенте, значит правится без пересборки мода. Запуск меню: /lore emit <ник> polygon.menu
-- (dev.sh polygon расставит сцену и напечатает команды).

lore.log("polygon 0.46: тестовый стенд загружен")

-- ─────────────────────────────────────────────────────────
-- Крен камеры. Катсцена roll_test качает горизонт вправо/влево вокруг игрока.
-- Якорь — позиция игрока, разворот по его же yaw, чтобы облёт шёл спереди.
-- ─────────────────────────────────────────────────────────
local function play_roll()
  local p = lore.player()
  if not p then return end
  lore.emit("cutscene.play", {
    id = "roll_test",
    x = p.x, y = p.y, z = p.z, yaw = p.yaw,
  })
end
lore.on("polygon.roll", play_roll)

-- ─────────────────────────────────────────────────────────
-- Экранная вуаль. Медленный уход в чёрное и обратно; отдельно — быстрая красная
-- вспышка (та самая огибающая in/hold/out, что раньше собиралась костылём).
-- ─────────────────────────────────────────────────────────
lore.on("polygon.fade", function()
  lore.emit("screen.fade", { color = "#FF000000", ["in"] = 1.5, hold = 1.0, out = 1.5 })
end)

lore.on("polygon.flash", function()
  lore.emit("screen.fade", { color = "#AAFF2020", ["in"] = 0.05, hold = 0.05, out = 0.6 })
end)

-- ─────────────────────────────────────────────────────────
-- Луч видимости. Три замера: вперёд по взгляду (сравнить с target()), вверх (небо
-- должно быть clear) и вниз (пол — не clear). Пишет в лог клиента, куда упёрся.
-- ─────────────────────────────────────────────────────────
local function ray_report(label, from, to)
  local v = lore.visible(from[1], from[2], from[3], to[1], to[2], to[3])
  if not v then
    lore.log(label .. ": lore.visible вернул nil (мир не готов?)")
  elseif v.clear then
    lore.log(label .. ": СВОБОДНО")
  else
    lore.log(string.format("%s: перекрыто на %.1f блока — %s (%d %d %d)",
      label, v.distance or -1, tostring(v.id), v.block_x, v.block_y, v.block_z))
  end
end

lore.on("polygon.look", function()
  local p = lore.player()
  if not p then return end
  local eye = { p.x, p.y + 1.62, p.z }

  -- Направление взгляда → точка в 30 блоках впереди.
  local yaw = math.rad(p.yaw)
  local pitch = math.rad(p.pitch)
  local dx = -math.sin(yaw) * math.cos(pitch)
  local dy = -math.sin(pitch)
  local dz = math.cos(yaw) * math.cos(pitch)
  ray_report("взгляд ×30", eye, { eye[1] + dx * 30, eye[2] + dy * 30, eye[3] + dz * 30 })

  ray_report("вверх ×20", eye, { eye[1], eye[2] + 20, eye[3] })
  ray_report("вниз ×5", eye, { eye[1], eye[2] - 5, eye[3] })

  -- Сверка с target(): что игра сама считает под прицелом.
  local t = lore.target()
  if t then
    lore.log(string.format("target(): %s на %.1f (%s)",
      tostring(t.type), t.distance or -1, tostring(t.id or t.entity_type)))
  else
    lore.log("target(): прицел в пустоте")
  end
end)

-- ─────────────────────────────────────────────────────────
-- Меню-хаб. Кнопки дёргают локальные эффекты; верховая езда — командой с сервера
-- (клиентская посадка рассинхронизировалась бы), поэтому здесь только подпись.
-- ─────────────────────────────────────────────────────────
lore.on("polygon.menu", function()
  -- Захватываем handle экрана как upvalue: катсцена не видна из-под открытого GUI,
  -- поэтому перед креном закрываемся. Присваивается ниже, замыкание увидит значение.
  local panel

  local nodes = ui.merge(
    ui.panel { w = 260, h = 210, title = "§6Полигон 0.46.0" },
    {
      ui.text { anchor = "center", x = 0, y = -80, align = "center",
        text = "§7четыре примитива, не проверенных живьём", color = "#FFAAAAAA" },

      ui.button { anchor = "center", x = -120, y = -58, w = 240, h = 22,
        label = "Крен катсцены (roll)",
        on_click = function() if panel then panel.close() end; play_roll() end },

      -- Вуаль рисуется слоем HUD, а тот не идёт поверх открытого GUI: не закрыв
      -- панель, эффект увидеть нельзя вовсе — закрываемся и здесь.
      ui.button { anchor = "center", x = -120, y = -32, w = 116, h = 22,
        label = "Фейд в чёрное", color = "#FF1A1A2A", hover = "#FF2A2A4A",
        on_click = function()
          if panel then panel.close() end
          lore.emit("screen.fade", { color = "#FF000000", ["in"] = 1.5, hold = 1.0, out = 1.5 })
        end },
      ui.button { anchor = "center", x = 4, y = -32, w = 116, h = 22,
        label = "Красная вспышка", color = "#FF3A1A1A", hover = "#FF5A2A2A",
        on_click = function()
          if panel then panel.close() end
          lore.emit("screen.fade", { color = "#AAFF2020", ["in"] = 0.05, hold = 0.05, out = 0.6 })
        end },

      ui.button { anchor = "center", x = -120, y = -6, w = 240, h = 22,
        label = "Луч видимости → лог клиента",
        color = "#FF1A2A2A", hover = "#FF2A4A4A",
        on_click = function() lore.emit("polygon.look", {}) end },

      ui.text { anchor = "center", x = 0, y = 26, align = "center",
        text = "§eВерховая езда — командой в консоль:", color = "#FFFFD080" },
      ui.text { anchor = "center", x = 0, y = 40, align = "center",
        text = "§7/lore ride <ник> 1 0 1.4 0", color = "#FFAAAAAA" },
      ui.text { anchor = "center", x = 0, y = 52, align = "center",
        text = "§7/lore ride <ник> off", color = "#FFAAAAAA" },

      ui.text { anchor = "center", x = 0, y = 80, align = "center",
        text = "§8Esc — закрыть", color = "#FF888888" },
    }
  )

  panel = lore.screen {
    title = "Полигон",
    nodes = nodes,
    on_close = function() lore.log("полигон: меню закрыто") end,
  }
end)
