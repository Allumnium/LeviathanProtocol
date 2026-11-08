class_name TradeSystem
extends RefCounted

static func ammunition_quote(content: DefDatabase) -> Dictionary:
	var economy := content.get_def("economy", "core:default")
	return {"count": int(economy.missile_pack_size), "price": int(economy.missile_pack_price)}

static func buy_ammunition(tx: RunTransaction, content: DefDatabase) -> bool:
	var quote := ammunition_quote(content)
	if tx.doc.fleet.credits < quote.price:
		tx.error = "Not enough credits. Cost: %d." % quote.price
		return false
	if tx.doc.fleet.missiles > 2147483647 - quote.count:
		tx.error = "Missile storage limit reached."
		return false
	tx.doc.fleet.credits -= quote.price
	tx.doc.fleet.missiles += quote.count
	tx.doc.chronicle.append({"id": tx.doc.chronicle.size() + 1, "type": "trade.completed",
		"seconds": tx.doc.clock.seconds, "data": {"kind": "ammunition", "count": quote.count, "credits": quote.price}})
	tx.emit_hook("trade.completed", {"kind": "ammunition", "count": quote.count, "credits": quote.price})
	return true
