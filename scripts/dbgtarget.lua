-- Отладка прицела: раз в секунду докладывает серверу, что клиент считает целью.
-- Нужен, потому что «клик не сработал» неотличимо от «клиент не видит блок»:
-- сервер знает только про пришедший пакет, а решение о цели принимает клиент.
-- Включить:  /lore emit to <ник> dbgtarget.on     снять: dbgtarget.off

local stop = nil

lore.on("dbgtarget.on", function()
    if stop then return end
    stop = lore.every(1, function()
        local t = lore.target()
        if t == nil then
            lore.report("dbg.target", { hit = "нет" })
        else
            lore.report("dbg.target", t)
        end
    end)
end)

lore.on("dbgtarget.off", function()
    if stop then stop(); stop = nil end
end)

-- Надпись над блоком приходит маркером; проверить её иначе нечем — клиент рисует
-- маркеры молча, а сервер знает только, что отправил пакет.
lore.on("marker.set", function(data)
    if data and data.type == "text" then
        lore.report("dbg.marker", { id = data.id, text = data.text })
    end
end)
