// Reference implementation copied VERBATIM from erp.webapp/src/views/warehouse/packScanBatch.vue
// (processItem, lines 477-539) to differential-test lib/pages/picklist/picklist_service.dart buildBatchPrintlist.
const cases = JSON.parse(require('fs').readFileSync(0, 'utf8'))
function run(alreadyPrintedQty) {
  let thisListQty = 0
            const limitQty = alreadyPrintedQty + this.inputItemQty
            const _printlist = []
            for (const _order of this.orders) {
              if (limitQty <= thisListQty) {
                break
              }
              // find itemPack
              let itemPack = null
              if (_order.itemPacks) {
                for (const _itemPack of _order.itemPacks) {
                  if (_itemPack.sku === this.inputItemID) {
                    itemPack = _itemPack
                    break
                  }
                }
              }
              if (itemPack === null) {
                let itemSum = 0
                for (const _item of _order.items) {
                  if (_item.sku === this.inputItemID) {
                    itemPack = JSON.parse(JSON.stringify(_item))
                    itemPack.lblIdx = Array.from(Array(itemSum + _item.qty).keys()).slice(itemSum)
                    break
                  }
                  itemSum += _item.qty
                }
              }
              if (itemPack === null) {
                continue
              }

              if (
                thisListQty < alreadyPrintedQty &&
                thisListQty + itemPack.lblIdx.length > alreadyPrintedQty
              ) {
                const lblrest = alreadyPrintedQty - thisListQty
                thisListQty += lblrest
                const rest = Math.min(limitQty - thisListQty, itemPack.lblIdx.length - lblrest)
                _printlist.push({
                  UNID: _order.UNID,
                  id: _order.ID,
                  packSKU: this.inputItemID,
                  lblIdx: itemPack.lblIdx.slice(lblrest, lblrest + rest),
                  packingMaterials: this.inputPackMaterial,
                  initiator: 'packScanBatch'
                })
                thisListQty += rest
              } else if (thisListQty < alreadyPrintedQty) {
                thisListQty += itemPack.lblIdx.length
              } else if (thisListQty >= alreadyPrintedQty) {
                _printlist.push({
                  UNID: _order.UNID,
                  id: _order.ID,
                  packSKU: this.inputItemID,
                  lblIdx: itemPack.lblIdx.slice(0, limitQty - thisListQty),
                  packingMaterials: this.inputPackMaterial,
                  initiator: 'packScanBatch'
                })
                thisListQty += Math.min(itemPack.lblIdx.length, limitQty - thisListQty)
              } else if (thisListQty + itemPack.lblIdx.length === alreadyPrintedQty) {
                thisListQty += itemPack.lblIdx.length
              }
            }
  return _printlist
}
const out = cases.map(c => run.call({ orders: c.orders, inputItemID: c.sku, inputItemQty: c.qty, inputPackMaterial: c.materials }, c.alreadyPrinted))
process.stdout.write(JSON.stringify(out))
