/// Translations (en / zh / de). English is the default, like the web app.
///
/// Lookup order for `tr(key)`:
///   1. `pda.*` keys below (texts that only exist on the PDA)
///   2. web keys (`wms.*`, `common.*` ...) copied from erp.webapp/src/locale by
///      tool/sync_web_locale.py into web_locale.g.dart -> identical wording to the web.
/// `{name}` placeholders are filled from [args].
library;

import 'web_locale.g.dart';

String _lang = 'en';

const supportedLanguages = {'en': 'English', 'zh': '中文', 'de': 'Deutsch'};

void setLanguage(String lang) {
  _lang = supportedLanguages.containsKey(lang) ? lang : 'en';
}

String get currentLanguage => _lang;

String tr(String key, [Map<String, Object?> args = const {}]) {
  final row = _pda[key] ?? webLocale[key];
  var s = row == null ? key : (row[_lang] ?? row['en'] ?? key);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  return s;
}

/// Exposed for the translation-completeness test.
Map<String, Map<String, String>> get translationTable => {...webLocale, ..._pda};

const Map<String, Map<String, String>> _pda = {
  // ---------- general ----------
  'pda.all': {'en': 'All', 'zh': '全部', 'de': 'Alle'},
  'pda.total': {'en': 'Total {n}', 'zh': '共 {n} 条', 'de': 'Gesamt {n}'},
  'pda.loadMore': {'en': 'Load more', 'zh': '加载更多', 'de': 'Mehr laden'},
  'pda.noData': {'en': 'No data', 'zh': '暂无数据', 'de': 'Keine Daten'},
  'pda.notFound': {'en': '{code} not found', 'zh': '未找到 {code}', 'de': '{code} nicht gefunden'},
  'pda.inputCode': {'en': 'Enter barcode', 'zh': '输入条码', 'de': 'Barcode eingeben'},
  'pda.busyWait': {'en': 'Still processing the previous scan', 'zh': '上一条还在处理，请稍候再扫', 'de': 'Vorheriger Scan läuft noch'},
  'pda.save': {'en': 'Save', 'zh': '保存', 'de': 'Speichern'},
  'pda.saved': {'en': 'Saved', 'zh': '已保存', 'de': 'Gespeichert'},
  'pda.delete': {'en': 'Delete', 'zh': '删除', 'de': 'Löschen'},
  'pda.history': {'en': 'Scan History', 'zh': '扫描记录', 'de': 'Scan-Verlauf'},
  'pda.logoutConfirm': {'en': 'Log out now?', 'zh': '确定退出登录？', 'de': 'Jetzt abmelden?'},
  'pda.pickScanBatch': {'en': 'Pick Scan Batch', 'zh': 'Pick Scan Batch', 'de': 'Pick Scan Batch'},
  'pda.packScanOrder': {'en': 'Pack Scan Order', 'zh': 'Pack Scan Order', 'de': 'Pack Scan Order'},

  // ---------- errors / network ----------
  'pda.err.notSent': {
    'en': 'No network - the request was not sent. Move to better Wi-Fi and scan again.',
    'zh': '网络不通，请求未发出。请移动到信号好的位置后重扫。',
    'de': 'Kein Netz - Anfrage nicht gesendet. Bessere WLAN-Position suchen und erneut scannen.'
  },
  'pda.err.unknown': {
    'en': 'Timeout: the server may or may not have processed it. Check the result before scanning again!',
    'zh': '网络超时：服务器可能已处理也可能没有。请先核对结果，不要直接重复扫描！',
    'de': 'Zeitüberschreitung: evtl. bereits verarbeitet. Ergebnis prüfen, nicht einfach erneut scannen!'
  },
  'pda.err.verified': {
    'en': 'The progress above was re-read from the server.',
    'zh': '上面的进度已从服务器重新读取。',
    'de': 'Der Fortschritt oben wurde neu vom Server gelesen.'
  },
  'pda.err.auth': {'en': 'Your session has expired, please login again.', 'zh': '登录已过期，请重新登录', 'de': 'Sitzung abgelaufen, bitte neu anmelden'},
  'pda.err.server': {'en': 'Server error {code}', 'zh': '服务器错误 {code}', 'de': 'Serverfehler {code}'},
  'pda.err.http400': {
    'en': 'Request rejected (400). Check the Origin in Settings.',
    'zh': '服务器拒绝请求 (400)。请在设置中检查 Origin。',
    'de': 'Anfrage abgelehnt (400). Origin in den Einstellungen prüfen.'
  },
  'pda.net.good': {'en': 'Online', 'zh': '网络良好', 'de': 'Online'},
  'pda.net.slowShort': {'en': 'Slow network', 'zh': '网络较慢', 'de': 'Langsames Netz'},
  'pda.net.offlineShort': {'en': 'Offline', 'zh': '网络断开', 'de': 'Offline'},
  'pda.net.offline': {
    'en': 'No network. Scans cannot be submitted - move to an area with Wi-Fi.',
    'zh': '当前无网络，扫描无法提交，请移动到有信号的区域。',
    'de': 'Kein Netz. Scans werden nicht übertragen - in WLAN-Bereich wechseln.'
  },
  'pda.net.slow': {
    'en': 'Slow network - wait for each result before the next scan.',
    'zh': '网络较慢，请等结果出来再扫下一个。',
    'de': 'Langsames Netz - auf jedes Ergebnis warten.'
  },

  // ---------- login ----------
  'pda.login.account': {'en': 'Account (e-mail)', 'zh': '账号（邮箱）', 'de': 'Konto (E-Mail)'},
  'pda.login.captchaTap': {'en': 'Tap to refresh', 'zh': '点击刷新', 'de': 'Antippen'},
  'pda.login.required': {'en': 'Please fill in account, password and captcha', 'zh': '请填写账号、密码和验证码', 'de': 'Bitte Konto, Passwort und Captcha ausfüllen'},
  'pda.login.failed': {'en': 'Login failed: {msg}', 'zh': '登录失败：{msg}', 'de': 'Anmeldung fehlgeschlagen: {msg}'},
  'pda.login.relogin': {'en': 'Session expired!', 'zh': '登录已过期', 'de': 'Sitzung abgelaufen!'},
  'pda.login.reloginHint': {
    'en': 'Sign in again to continue - the current screen is kept.',
    'zh': '重新登录后可继续当前操作（当前页面数据会保留）。',
    'de': 'Erneut anmelden, um fortzufahren - die Seite bleibt erhalten.'
  },
  'pda.login.toLoginPage': {'en': 'Back to login', 'zh': '返回登录页', 'de': 'Zur Anmeldung'},
  'pda.login.renewed': {
    'en': 'Signed in again. The last scan was not submitted - please scan it again.',
    'zh': '已重新登录。上一条扫描没有提交，请重新扫描。',
    'de': 'Wieder angemeldet. Der letzte Scan wurde nicht übertragen - bitte erneut scannen.'
  },

  // ---------- picklist ----------
  'pda.pick.todo': {'en': 'To do', 'zh': '待处理', 'de': 'Offen'},
  'pda.pick.change': {'en': 'Change Picklist', 'zh': 'Change Picklist', 'de': 'Change Picklist'},
  'pda.pick.next': {'en': 'Next Picklist', 'zh': '扫描下一个 Picklist', 'de': 'Nächste Picklist'},
  'pda.pick.finished': {'en': 'This Picklist is Finished!', 'zh': 'This Picklist is Finished!', 'de': 'This Picklist is Finished!'},
  'pda.pick.countAgain': {'en': 'Please count again!', 'zh': 'Please count again!', 'de': 'Please count again!'},
  'pda.pick.notEnoughLabels': {'en': 'Not enough labels to print!', 'zh': 'Not enough labels to print!', 'de': 'Not enough labels to print!'},
  'pda.pick.scanAgain': {'en': 'Please scan the item again!', 'zh': 'Please scan the item again!', 'de': 'Please scan the item again!'},
  'pda.pick.orderMaybeCanceled': {'en': 'Order maybe canceled!', 'zh': 'Order maybe canceled!', 'de': 'Order maybe canceled!'},
  'pda.pick.shipmentLabel': {'en': 'Shipment Label', 'zh': 'Shipment Label', 'de': 'Shipment Label'},
  'pda.pick.printing': {'en': 'Label sent to the print station', 'zh': '面单已发送到打印站', 'de': 'Etikett an Druckstation gesendet'},
  'pda.pick.picked': {'en': 'picked', 'zh': '已拣', 'de': 'gepickt'},
  'pda.pick.saveFailed': {
    'en': 'The labels were requested but the picklist progress could not be saved. Check the picklist on the PC.',
    'zh': '面单已申请，但拣料进度保存失败。请在电脑端核对该 Picklist。',
    'de': 'Etiketten angefordert, Fortschritt nicht gespeichert. Pickliste am PC prüfen.'
  },
  'pda.pick.requestLabelOnPc': {
    'en': 'This order has no shipment label yet - request it at the PC (Pack Scan Order).',
    'zh': '该订单还没有运单，请在电脑端 Pack Scan Order 中申请。',
    'de': 'Noch kein Versandetikett - bitte am PC anfordern (Pack Scan Order).'
  },
  'pda.pick.st7': {'en': 'Partially Shipped', 'zh': '部分发货', 'de': 'Teilweise versandt'},
  'pda.pick.st101': {'en': 'Done without waybill', 'zh': '无运单完成', 'de': 'Ohne Frachtbrief erledigt'},
  'pda.pick.st102': {'en': 'Done without shipping', 'zh': '无发货完成', 'de': 'Ohne Versand erledigt'},

  // ---------- print station ----------
  'pda.print.notConfigured': {
    'en': 'Print station not set: Settings > Print station (PrintBridge)',
    'zh': '未设置打印站：设置 > 打印站 (PrintBridge)',
    'de': 'Druckstation fehlt: Einstellungen > Druckstation (PrintBridge)'
  },
  'pda.print.failed': {'en': 'Printing failed: {msg}', 'zh': '打印失败：{msg}', 'de': 'Drucken fehlgeschlagen: {msg}'},

  // ---------- loading scan ----------
  'pda.plt.loaded': {'en': 'Loaded {n}', 'zh': '已装车 {n}', 'de': 'Verladen {n}'},
  'pda.plt.pending': {'en': 'Pending {n}', 'zh': '待提交 {n}', 'de': 'Ausstehend {n}'},
  'pda.plt.queued': {'en': 'Queued {code}', 'zh': '已加入队列 {code}', 'de': 'Eingereiht {code}'},
  'pda.plt.flushError': {'en': 'Submit failed: {msg}', 'zh': '提交失败：{msg}', 'de': 'Übertragung fehlgeschlagen: {msg}'},
  'pda.plt.offlineQueued': {
    'en': 'No network - saved on this device, submitted automatically when back online',
    'zh': '无网络，已保存在本机，恢复网络后自动提交',
    'de': 'Offline - lokal gespeichert, wird automatisch übertragen'
  },
  'pda.plt.removeConfirm': {'en': 'Remove {code} from the pallet?', 'zh': '从托盘移除 {code}？', 'de': '{code} von der Palette entfernen?'},
  'pda.plt.removePending': {'en': 'Drop pending scan {code}?', 'zh': '删除待提交 {code}？', 'de': 'Ausstehenden Scan {code} verwerfen?'},
  'pda.plt.switchConfirm': {
    'en': '{n} scans are still pending; they stay saved on this device for this pallet. Continue?',
    'zh': '还有 {n} 条待提交，会保存在本机该托盘的队列中。继续？',
    'de': '{n} Scans ausstehend; sie bleiben für diese Palette gespeichert. Fortfahren?'
  },

  // ---------- RMA ----------
  'pda.rma.pending': {'en': 'Not inbounded', 'zh': '未入库', 'de': 'Nicht eingelagert'},
  'pda.rma.new': {'en': 'New', 'zh': '新建', 'de': 'Neu'},
  'pda.rma.opened': {'en': 'opened', 'zh': '已打开', 'de': 'geöffnet'},
  'pda.rma.createFailed': {'en': 'The RMA could not be created', 'zh': 'RMA 创建失败', 'de': 'RMA konnte nicht angelegt werden'},
  'pda.rma.discard': {'en': 'Discard unsaved changes?', 'zh': '放弃未保存的修改？', 'de': 'Ungespeicherte Änderungen verwerfen?'},
  'pda.rma.noItems': {'en': 'Scan the items first', 'zh': '请先扫描商品', 'de': 'Bitte zuerst Artikel scannen'},
  'pda.rma.customerRequired': {'en': 'Select the customer first', 'zh': '请先选择客户', 'de': 'Bitte zuerst den Kunden wählen'},
  'pda.rma.originItems': {'en': 'Items of the original order', 'zh': '原订单商品', 'de': 'Artikel des Originalauftrags'},
  'pda.rma.photo': {'en': 'Take photo', 'zh': '拍照', 'de': 'Foto'},
  'pda.rma.photoUploaded': {'en': 'Photo uploaded', 'zh': '照片已上传', 'de': 'Foto hochgeladen'},
  'pda.rma.inboundHint': {
    'en': 'Scan a location: it is set for every line without one. Tap a line first to set only that line.',
    'zh': '扫描库位：自动填给所有未设置库位的行。先点选某一行，则只设置该行。',
    'de': 'Lagerplatz scannen: gilt für alle Zeilen ohne Platz. Zeile antippen, um nur diese zu setzen.'
  },
  'pda.rma.scanLocationAll': {'en': 'Location? (all open lines)', 'zh': '扫描库位（所有未设置行）', 'de': 'Lagerplatz? (alle offenen Zeilen)'},
  'pda.rma.scanLocationOne': {'en': 'Location for {sku}?', 'zh': '扫描 {sku} 的库位', 'de': 'Lagerplatz für {sku}?'},
  'pda.rma.locationRequired': {'en': 'Every line needs a location', 'zh': '每一行都需要库位', 'de': 'Jede Zeile braucht einen Lagerplatz'},
  'pda.rma.inboundConfirm': {
    'en': 'Book {n} piece(s) into stock and mark the RMA as inbounded?',
    'zh': '确认将 {n} 件入库，并将该 RMA 标记为已入库？',
    'de': '{n} Stück einlagern und RMA als eingelagert markieren?'
  },
  'pda.rma.st1': {'en': 'Pending Inbound', 'zh': '待入库', 'de': 'Einlagerung ausstehend'},
  'pda.rma.st2': {'en': 'Receiving', 'zh': '收货中', 'de': 'Im Wareneingang'},
  'pda.rma.st8': {'en': 'Counting', 'zh': '清点中', 'de': 'Zählung'},
  'pda.rma.st10': {'en': 'Inbound list generated', 'zh': '已生成入库清单', 'de': 'Einlagerliste erstellt'},

  // ---------- shipping / inventory ----------
  'pda.ship.phSKU': {'en': 'Please scan SKU for QC', 'zh': 'Please scan SKU for QC', 'de': 'Please scan SKU for QC'},
  'pda.ship.phSN': {'en': 'Please scan item serial number', 'zh': 'Please scan item serial number', 'de': 'Please scan item serial number'},
  'pda.stk.scan': {'en': 'Location / Item ID / Barcode', 'zh': '库位 / 物品编号 / 条码', 'de': 'Lagerplatz / Artikel-ID / Barcode'},

  // ---------- history ----------
  'pda.his.empty': {'en': 'No scans yet', 'zh': '还没有扫描记录', 'de': 'Noch keine Scans'},
  'pda.his.clearConfirm': {'en': 'Clear the scan history on this device?', 'zh': '清空本机扫描记录？', 'de': 'Verlauf auf diesem Gerät löschen?'},
  'pda.his.ok': {'en': 'OK', 'zh': '成功', 'de': 'OK'},
  'pda.his.warn': {'en': 'Warning', 'zh': '提醒', 'de': 'Warnung'},
  'pda.his.error': {'en': 'Failed', 'zh': '失败', 'de': 'Fehler'},
  'pda.his.unknown': {'en': 'Unknown', 'zh': '结果未知', 'de': 'Unklar'},
  'pda.his.queued': {'en': 'Queued', 'zh': '排队中', 'de': 'Eingereiht'},

  // ---------- settings ----------
  'pda.set.test': {'en': 'Scanner test: scan any barcode', 'zh': '扫描测试：请扫任意条码', 'de': 'Scannertest: beliebigen Code scannen'},
  'pda.set.printStation': {'en': 'Print station (PrintBridge)', 'zh': '打印站 (PrintBridge)', 'de': 'Druckstation (PrintBridge)'},
  'pda.set.printHost': {'en': 'Print station PC (IP[:port])', 'zh': '打印站电脑 (IP[:端口])', 'de': 'Druckstation-PC (IP[:Port])'},
  'pda.set.printer': {'en': 'Printer', 'zh': '打印机', 'de': 'Drucker'},
  'pda.set.printerOk': {'en': 'Connected, {n} printer(s)', 'zh': '已连接，{n} 台打印机', 'de': 'Verbunden, {n} Drucker'},
  'pda.set.scanner': {'en': 'Scanner', 'zh': '扫描头', 'de': 'Scanner'},
  'pda.set.scannerMode': {'en': 'Broadcast mode', 'zh': '广播模式', 'de': 'Broadcast-Modus'},
  'pda.set.scannerAuto': {'en': 'Auto (iData and other brands)', 'zh': '自动（兼容 iData 等主流品牌）', 'de': 'Automatisch (iData und andere)'},
  'pda.set.scannerNone': {'en': 'Off', 'zh': '关闭广播', 'de': 'Aus'},
  'pda.set.scannerCustom': {'en': 'Custom only', 'zh': '仅自定义', 'de': 'Nur benutzerdefiniert'},
  'pda.set.customAction': {'en': 'Custom broadcast action', 'zh': '自定义广播 Action', 'de': 'Eigene Broadcast-Action'},
  'pda.set.customExtra': {'en': 'Custom extra key', 'zh': '自定义数据 Extra 键', 'de': 'Eigener Extra-Schlüssel'},
  'pda.set.wedge': {'en': 'Keyboard mode scanning (Enter suffix)', 'zh': '键盘模式扫描（以回车结尾）', 'de': 'Tastatur-Modus (mit Enter)'},
  'pda.set.feedback': {'en': 'Feedback', 'zh': '提示', 'de': 'Rückmeldung'},
  'pda.set.sound': {'en': 'Sound', 'zh': '提示音', 'de': 'Ton'},
  'pda.set.vibrate': {'en': 'Vibration', 'zh': '震动', 'de': 'Vibration'},
  'pda.set.keepScreenOn': {'en': 'Keep screen on', 'zh': '屏幕常亮', 'de': 'Bildschirm anlassen'},
  'pda.set.testBeep': {'en': 'Test sound', 'zh': '测试提示音', 'de': 'Ton testen'},
  'pda.set.language': {'en': 'Language', 'zh': '语言', 'de': 'Sprache'},
  'pda.set.network': {'en': 'Network', 'zh': '网络', 'de': 'Netzwerk'},
  'pda.set.server': {'en': 'Server', 'zh': '服务器', 'de': 'Server'},
  'pda.set.serverChanged': {'en': 'Server changed - please log in again', 'zh': '服务器已更改，请重新登录', 'de': 'Server geändert - bitte neu anmelden'},
  'pda.set.origin': {'en': 'Origin (allow-listed web domain)', 'zh': 'Origin（跨域白名单域名）', 'de': 'Origin (freigegebene Domain)'},
  'pda.set.connectTimeout': {'en': 'Connect timeout (s)', 'zh': '连接超时（秒）', 'de': 'Verbindungs-Timeout (s)'},
  'pda.set.receiveTimeout': {'en': 'Response timeout (s)', 'zh': '响应超时（秒）', 'de': 'Antwort-Timeout (s)'},
  'pda.set.checkNow': {'en': 'Check', 'zh': '检测', 'de': 'Prüfen'},
  'pda.set.about': {'en': 'About', 'zh': '关于', 'de': 'Info'},
  'pda.set.device': {'en': 'Device', 'zh': '设备', 'de': 'Gerät'},
};
