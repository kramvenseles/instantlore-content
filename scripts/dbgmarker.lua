-- Временная отладка: докладывать серверу каждый пришедший текстовый маркер.
-- Клиент рисует маркеры молча, а сервер знает лишь, что отправил пакет, —
-- без этого «надпись показана» и «надпись отправлена» неразличимы.
lore.on("marker.set", function(data)
    if data and data.type == "text" then
        lore.report("dbg.marker", { id = data.id, y = data.y, text = data.text })
    end
end)
