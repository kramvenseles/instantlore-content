-- Временно: докладывать серверу каждый пришедший текстовый маркер (id, высота, текст).
lore.on("marker.set", function(data)
    if data and data.type == "text" then
        lore.report("dbg.marker", { id = data.id, y = data.y, text = data.text })
    end
end)
