-- Динамический интерактивный экран из ui.lua. Всё живёт в контенте: и библиотека виджетов,
-- и этот скрипт. Клик обрабатывается Lua-замыканием ЛОКАЛЬНО (без сервера), меняет состояние
-- и перерисовывает экран. Ровно то, ради чего морозили только геометрию.
-- Запуск: /lore emit <ник> demo.menu
lore.on("demo.menu", function()
  local count = 0
  local render

  render = function()
    local nodes = ui.merge(
      ui.panel { w = 220, h = 140, title = "§6Реактивный счётчик" },
      {
        ui.text { anchor = "center", x = 0, y = -34, align = "center", text = "Нажатий: " .. count },
        ui.button { anchor = "center", x = -95, y = -8, w = 60, h = 22, label = "−1",
          on_click = function() count = count - 1; render() end },
        ui.button { anchor = "center", x = 35, y = -8, w = 60, h = 22, label = "+1",
          on_click = function() count = count + 1; render() end },
        ui.button { anchor = "center", x = -60, y = 26, w = 120, h = 22, label = "Доклад серверу",
          color = "#FF2A4A2A", hover = "#FF3A6A3A",
          on_click = function() lore.report("demo.counter", { value = count }) end },
        ui.text { anchor = "center", x = 0, y = 54, align = "center",
          text = "§7Esc — закрыть", color = "#FFAAAAAA" },
      }
    )

    lore.screen {
      title = "Счётчик",
      nodes = nodes,
      on_close = function() lore.log("меню закрыто, итог счёта = " .. count) end,
    }
  end

  render()
end)
