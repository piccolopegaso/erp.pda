/// Lightweight translations (zh / en / de) – no code generation needed.
/// Use `tr('key')` or `tr('key', {'n': 3})` for `{n}` placeholders.
library;

String _lang = 'zh';

const supportedLanguages = {'zh': '中文', 'en': 'English', 'de': 'Deutsch'};

void setLanguage(String lang) {
  _lang = supportedLanguages.containsKey(lang) ? lang : 'zh';
}

String get currentLanguage => _lang;

String tr(String key, [Map<String, Object?> args = const {}]) {
  final row = _t[key];
  var s = row == null ? key : (row[_lang] ?? row['en'] ?? key);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  return s;
}

/// Exposed for the translation-completeness test.
Map<String, Map<String, String>> get translationTable => _t;

const Map<String, Map<String, String>> _t = {
  // ---------- common ----------
  'app.title': {'zh': 'MIC 仓库 PDA', 'en': 'MIC Warehouse PDA', 'de': 'MIC Lager-PDA'},
  'common.ok': {'zh': '确定', 'en': 'OK', 'de': 'OK'},
  'common.cancel': {'zh': '取消', 'en': 'Cancel', 'de': 'Abbrechen'},
  'common.confirm': {'zh': '确认', 'en': 'Confirm', 'de': 'Bestätigen'},
  'common.retry': {'zh': '重试', 'en': 'Retry', 'de': 'Erneut'},
  'common.save': {'zh': '保存', 'en': 'Save', 'de': 'Speichern'},
  'common.close': {'zh': '关闭', 'en': 'Close', 'de': 'Schließen'},
  'common.clear': {'zh': '清空', 'en': 'Clear', 'de': 'Leeren'},
  'common.loading': {'zh': '处理中…', 'en': 'Working…', 'de': 'Bitte warten…'},
  'common.manualInput': {'zh': '手动输入', 'en': 'Type code', 'de': 'Code eingeben'},
  'common.inputCode': {'zh': '输入条码', 'en': 'Enter barcode', 'de': 'Barcode eingeben'},
  'common.next': {'zh': '下一个', 'en': 'Next', 'de': 'Nächstes'},
  'common.restart': {'zh': '重新开始', 'en': 'Start over', 'de': 'Neu beginnen'},
  'common.busyWait': {'zh': '上一条还在处理，请稍候再扫', 'en': 'Still processing the previous scan', 'de': 'Vorheriger Scan läuft noch'},
  'common.customer': {'zh': '客户', 'en': 'Customer', 'de': 'Kunde'},
  'common.items': {'zh': '商品', 'en': 'Items', 'de': 'Artikel'},
  'common.qty': {'zh': '数量', 'en': 'Qty', 'de': 'Menge'},
  'common.location': {'zh': '库位', 'en': 'Location', 'de': 'Lagerplatz'},
  'common.batch': {'zh': '批次', 'en': 'Batch', 'de': 'Charge'},
  'common.warehouse': {'zh': '仓库', 'en': 'Warehouse', 'de': 'Lager'},
  'common.status': {'zh': '状态', 'en': 'Status', 'de': 'Status'},
  'common.note': {'zh': '备注', 'en': 'Remark', 'de': 'Bemerkung'},
  'common.noteInner': {'zh': '内部备注', 'en': 'Internal remark', 'de': 'Interne Bemerkung'},
  'common.orderNo': {'zh': '单号', 'en': 'Order no.', 'de': 'Auftragsnr.'},
  'common.refNo': {'zh': '参考号', 'en': 'Ref. no.', 'de': 'Referenz'},
  'common.trackingNo': {'zh': '跟踪号', 'en': 'Tracking no.', 'de': 'Sendungsnr.'},
  'common.carrier': {'zh': '承运商', 'en': 'Carrier', 'de': 'Versender'},
  'common.consignee': {'zh': '收件人', 'en': 'Consignee', 'de': 'Empfänger'},
  'common.country': {'zh': '国家', 'en': 'Country', 'de': 'Land'},
  'common.scannedAt': {'zh': '扫描时间', 'en': 'Scanned at', 'de': 'Gescannt'},
  'common.notFound': {'zh': '未找到: {code}', 'en': 'Not found: {code}', 'de': 'Nicht gefunden: {code}'},
  'common.empty': {'zh': '暂无数据', 'en': 'No data', 'de': 'Keine Daten'},
  'common.lastScan': {'zh': '最近扫描', 'en': 'Last scan', 'de': 'Letzter Scan'},
  'common.waitScan': {'zh': '请扫描', 'en': 'Please scan', 'de': 'Bitte scannen'},
  'common.total': {'zh': '共 {n} 条', 'en': '{n} rows', 'de': '{n} Zeilen'},

  // ---------- errors / network ----------
  'err.network.notSent': {
    'zh': '网络不通，请求未发出。请移动到信号好的位置后重扫。',
    'en': 'No network – the request was not sent. Move to better Wi-Fi and scan again.',
    'de': 'Kein Netz – Anfrage nicht gesendet. Bessere WLAN-Position suchen und erneut scannen.'
  },
  'err.network.unknown': {
    'zh': '网络超时：服务器可能已处理也可能没有。请先核对结果，不要直接重复扫描！',
    'en': 'Timeout: the server may or may not have processed it. Check the result before scanning again!',
    'de': 'Zeitüberschreitung: evtl. bereits verarbeitet. Ergebnis prüfen, nicht einfach erneut scannen!'
  },
  'err.auth': {'zh': '登录已过期，请重新登录', 'en': 'Session expired, please log in again', 'de': 'Sitzung abgelaufen, bitte neu anmelden'},
  'err.server': {'zh': '服务器错误 {code}', 'en': 'Server error {code}', 'de': 'Serverfehler {code}'},
  'err.http400': {
    'zh': '服务器拒绝请求 (400)。请在设置中检查 Origin 是否正确。',
    'en': 'Request rejected (400). Check the Origin in settings.',
    'de': 'Anfrage abgelehnt (400). Origin in den Einstellungen prüfen.'
  },
  'err.unknownCheck': {'zh': '结果未知，已自动刷新以核对', 'en': 'Result unknown – refreshed to verify', 'de': 'Ergebnis unklar – zur Prüfung aktualisiert'},
  'net.good': {'zh': '网络良好', 'en': 'Online', 'de': 'Online'},
  'net.slow': {'zh': '网络较慢', 'en': 'Slow', 'de': 'Langsam'},
  'net.offline': {'zh': '网络断开', 'en': 'Offline', 'de': 'Offline'},
  'net.offlineBanner': {
    'zh': '当前无网络。扫描结果不会提交，请移动到信号好的区域。',
    'en': 'No network. Scans cannot be submitted – move to an area with Wi-Fi.',
    'de': 'Kein Netz. Scans werden nicht übertragen – in WLAN-Bereich wechseln.'
  },

  // ---------- login ----------
  'login.title': {'zh': '登录', 'en': 'Sign in', 'de': 'Anmelden'},
  'login.account': {'zh': '账号 (邮箱)', 'en': 'Account (e-mail)', 'de': 'Konto (E-Mail)'},
  'login.password': {'zh': '密码', 'en': 'Password', 'de': 'Passwort'},
  'login.captcha': {'zh': '验证码', 'en': 'Captcha', 'de': 'Captcha'},
  'login.captchaTap': {'zh': '点击图片刷新', 'en': 'Tap image to refresh', 'de': 'Bild antippen zum Aktualisieren'},
  'login.submit': {'zh': '登录', 'en': 'Sign in', 'de': 'Anmelden'},
  'login.server': {'zh': '服务器', 'en': 'Server', 'de': 'Server'},
  'login.failed': {'zh': '登录失败：{msg}', 'en': 'Login failed: {msg}', 'de': 'Anmeldung fehlgeschlagen: {msg}'},
  'login.required': {'zh': '请填写账号、密码和验证码', 'en': 'Please fill in account, password and captcha', 'de': 'Bitte Konto, Passwort und Captcha ausfüllen'},
  'login.relogin': {'zh': '重新登录', 'en': 'Sign in again', 'de': 'Erneut anmelden'},
  'login.reloginHint': {
    'zh': '会话已过期。重新登录后可继续当前操作（当前页面数据会保留）。',
    'en': 'Your session expired. Sign in to continue – the current screen is kept.',
    'de': 'Sitzung abgelaufen. Nach der Anmeldung geht es auf dieser Seite weiter.'
  },
  'login.renewed': {
    'zh': '已重新登录。上一条扫描没有提交，请重新扫描。',
    'en': 'Signed in again. The last scan was not submitted – please scan it again.',
    'de': 'Wieder angemeldet. Der letzte Scan wurde nicht übertragen – bitte erneut scannen.'
  },
  'login.toLoginPage': {'zh': '返回登录页', 'en': 'Back to login', 'de': 'Zur Anmeldung'},

  // ---------- home ----------
  'home.hello': {'zh': '你好，{name}', 'en': 'Hello, {name}', 'de': 'Hallo, {name}'},
  'home.logout': {'zh': '退出登录', 'en': 'Log out', 'de': 'Abmelden'},
  'home.logoutConfirm': {'zh': '确定退出登录？', 'en': 'Log out now?', 'de': 'Jetzt abmelden?'},
  'home.sectionOutbound': {'zh': '出库', 'en': 'Outbound', 'de': 'Ausgang'},
  'home.sectionInbound': {'zh': '入库 / 退货', 'en': 'Inbound / Returns', 'de': 'Eingang / Retouren'},
  'home.sectionStock': {'zh': '库存', 'en': 'Stock', 'de': 'Bestand'},
  'home.sectionOther': {'zh': '其他', 'en': 'Other', 'de': 'Sonstiges'},

  // ---------- module names ----------
  'mod.shipping': {'zh': '出库扫描', 'en': 'Shipping scan', 'de': 'Versandscan'},
  'mod.shipping.desc': {'zh': '出库复核 / SKU质检 / SN', 'en': 'Outbound QC, SKU check, SN', 'de': 'Ausgangskontrolle, SKU, SN'},
  'mod.pallet': {'zh': '装车交接', 'en': 'Pallet loading', 'de': 'Verladung'},
  'mod.pallet.desc': {'zh': '扫托盘/车牌，再扫跟踪号', 'en': 'Scan pallet, then parcels', 'de': 'Palette, dann Sendungen'},
  'mod.pick': {'zh': '拣货指引', 'en': 'Pick guide', 'de': 'Kommissionierhilfe'},
  'mod.pick.desc': {'zh': '按库位顺序拣货核对', 'en': 'Pick by location order', 'de': 'Nach Lagerplatz kommissionieren'},
  'mod.logging': {'zh': '扫描登记', 'en': 'Logging scan', 'de': 'Scan-Protokoll'},
  'mod.logging.desc': {'zh': '按任务登记箱号/标签', 'en': 'Log labels per task', 'de': 'Etiketten je Auftrag'},
  'mod.receiving': {'zh': '退货签收', 'en': 'Return receiving', 'de': 'Retourenannahme'},
  'mod.receiving.desc': {'zh': '扫退货单号，再扫商品', 'en': 'Scan return, then items', 'de': 'Retoure, dann Artikel'},
  'mod.snswap': {'zh': 'SN 换标', 'en': 'SN swap', 'de': 'SN-Tausch'},
  'mod.snswap.desc': {'zh': '扫订单与旧SN，远程打印新标', 'en': 'Swap SN, print remotely', 'de': 'SN tauschen, fern drucken'},
  'mod.stock': {'zh': '库存查询', 'en': 'Stock lookup', 'de': 'Bestandsabfrage'},
  'mod.stock.desc': {'zh': '扫库位或商品条码', 'en': 'Scan location or item', 'de': 'Lagerplatz oder Artikel'},
  'mod.history': {'zh': '扫描记录', 'en': 'Scan history', 'de': 'Scan-Verlauf'},
  'mod.history.desc': {'zh': '本机所有扫描结果', 'en': 'All scans on this device', 'de': 'Alle Scans dieses Geräts'},
  'mod.settings': {'zh': '设置', 'en': 'Settings', 'de': 'Einstellungen'},
  'mod.settings.desc': {'zh': '扫描头 / 声音 / 网络', 'en': 'Scanner, sound, network', 'de': 'Scanner, Ton, Netz'},

  // ---------- shipping scan ----------
  'ship.scanShipment': {'zh': '扫描 跟踪号 / FBA / 订单号', 'en': 'Scan tracking / FBA / order no.', 'de': 'Sendungs-/FBA-/Auftragsnr. scannen'},
  'ship.scanSKU': {'zh': '请扫描商品 SKU 质检：{item}', 'en': 'Scan SKU for QC: {item}', 'de': 'SKU zur Prüfung scannen: {item}'},
  'ship.scanSN': {'zh': '请扫描商品序列号：{item}', 'en': 'Scan serial number: {item}', 'de': 'Seriennummer scannen: {item}'},
  'ship.skuProgress': {'zh': 'SKU 质检 {a}/{b}', 'en': 'SKU QC {a}/{b}', 'de': 'SKU-Prüfung {a}/{b}'},
  'ship.snProgress': {'zh': 'SN {a}/{b}', 'en': 'SN {a}/{b}', 'de': 'SN {a}/{b}'},
  'ship.st91': {'zh': '需要扫描 SN', 'en': 'SN required', 'de': 'SN erforderlich'},
  'ship.st95': {'zh': '{a}/{b} 部分质检', 'en': '{a}/{b} partial QC', 'de': '{a}/{b} Teilprüfung'},
  'ship.st96': {'zh': '{a}/{b} 待承运商提货', 'en': '{a}/{b} ready for pickup', 'de': '{a}/{b} bereit zur Abholung'},
  'ship.st99': {'zh': '{a}/{b} 部分发货', 'en': '{a}/{b} partially shipped', 'de': '{a}/{b} teilversendet'},
  'ship.st100': {'zh': '{a}/{b} 已发货', 'en': '{a}/{b} shipped', 'de': '{a}/{b} versendet'},
  'ship.stDefault': {'zh': '{a}/{b} 已扫描', 'en': '{a}/{b} scanned', 'de': '{a}/{b} gescannt'},
  'ship.attention': {'zh': '注意！订单状态异常（可能已取消）', 'en': 'Attention! Check order status (maybe cancelled)', 'de': 'Achtung! Status prüfen (evtl. storniert)'},
  'ship.already': {'zh': '已扫描过 - {title}', 'en': 'Already scanned - {title}', 'de': 'Bereits gescannt - {title}'},
  'ship.bundles': {'zh': '已扫包裹', 'en': 'Scanned parcels', 'de': 'Gescannte Pakete'},
  'ship.missing': {'zh': '未扫', 'en': 'missing', 'de': 'fehlt'},
  'ship.cancelPrompt': {'zh': '退出质检/SN 扫描', 'en': 'Leave QC / SN scan', 'de': 'Prüfung verlassen'},
  'ship.skuScanned': {'zh': '已质检 SKU', 'en': 'SKU checked', 'de': 'Geprüfte SKU'},
  'ship.snScanned': {'zh': '已扫 SN', 'en': 'Scanned SN', 'de': 'Gescannte SN'},

  // ---------- receiving ----------
  'rcv.scanReturn': {'zh': '扫描退货跟踪号 / 运单号（扫两次确认）', 'en': 'Scan return / shipment no. (scan twice)', 'de': 'Retouren-/Sendungsnr. scannen (2× scannen)'},
  'rcv.scanAgain': {'zh': '请再扫一次 {code} 确认', 'en': 'Scan {code} again to confirm', 'de': '{code} zur Bestätigung erneut scannen'},
  'rcv.mismatch': {'zh': '两次扫描不一致，请重新扫描', 'en': 'Scans differ, please scan again', 'de': 'Scans verschieden, bitte erneut'},
  'rcv.scanItem': {'zh': '请扫描退货商品', 'en': 'Scan returned items', 'de': 'Retourenartikel scannen'},
  'rcv.gotItem': {'zh': '已登记 {code}', 'en': 'Got {code}', 'de': 'Erfasst: {code}'},
  'rcv.confirmInfo': {'zh': '请核对订单信息后扫描商品', 'en': 'Check the order and scan items', 'de': 'Auftrag prüfen, Artikel scannen'},
  'rcv.dispose': {'zh': '处理方式', 'en': 'Disposition', 'de': 'Behandlung'},
  'rcv.businessType': {'zh': '业务类型', 'en': 'Business type', 'de': 'Geschäftsart'},
  'rcv.nextPacket': {'zh': '下一个包裹', 'en': 'Next parcel', 'de': 'Nächstes Paket'},
  'rcv.firstScanned': {'zh': '首次扫描', 'en': 'First scanned', 'de': 'Erstmals gescannt'},
  'rcv.origItems': {'zh': '原订单商品', 'en': 'Original items', 'de': 'Ursprüngliche Artikel'},

  // ---------- logging ----------
  'log.scanTask': {'zh': '扫描任务号 / 订单号', 'en': 'Scan task / order no.', 'de': 'Auftragsnr. scannen'},
  'log.scanToLog': {'zh': '扫描标签进行登记', 'en': 'Scan labels to log', 'de': 'Etiketten zum Erfassen scannen'},
  'log.task': {'zh': '操作任务 {unid}', 'en': 'Task {unid}', 'de': 'Auftrag {unid}'},
  'log.inbound': {'zh': '入库单 {unid}', 'en': 'Inbound {unid}', 'de': 'Eingang {unid}'},
  'log.got': {'zh': '已登记 {code}', 'en': 'Logged {code}', 'de': 'Erfasst {code}'},
  'log.already': {'zh': '{code} 之前已登记', 'en': '{code} was logged before', 'de': '{code} war bereits erfasst'},
  'log.changeTask': {'zh': '更换任务', 'en': 'Change task', 'de': 'Auftrag wechseln'},

  // ---------- SN swap ----------
  'sn.scanOrder': {'zh': '扫描订单号（扫两次确认）', 'en': 'Scan order no. (scan twice)', 'de': 'Auftragsnr. scannen (2×)'},
  'sn.scanSN1': {'zh': '扫描原 SN（第1个）', 'en': 'Scan original SN #1', 'de': 'Original-SN #1 scannen'},
  'sn.scanSN2': {'zh': '扫描原 SN（第2个）', 'en': 'Scan original SN #2', 'de': 'Original-SN #2 scannen'},
  'sn.printed': {'zh': '新 SN {sn} 已发送到打印站', 'en': 'New SN {sn} sent to print station', 'de': 'Neue SN {sn} an Druckstation gesendet'},
  'sn.printFailed': {'zh': '远程打印失败：{msg}', 'en': 'Remote print failed: {msg}', 'de': 'Ferndruck fehlgeschlagen: {msg}'},
  'sn.history': {'zh': '打印历史（点击重新打印）', 'en': 'Print history (tap to reprint)', 'de': 'Druckverlauf (antippen = erneut)'},
  'sn.reprint': {'zh': '重新打印 {sn}？', 'en': 'Reprint {sn}?', 'de': '{sn} erneut drucken?'},
  'sn.changeOrder': {'zh': '更换订单', 'en': 'Change order', 'de': 'Auftrag wechseln'},

  // ---------- pallet ----------
  'plt.scanPallet': {'zh': '扫描托盘码 (LD/MP) 或车牌号', 'en': 'Scan pallet code (LD/MP) or plate', 'de': 'Palettencode (LD/MP) oder Kennzeichen scannen'},
  'plt.scanTracking': {'zh': '扫描跟踪号装车', 'en': 'Scan tracking numbers to load', 'de': 'Sendungsnummern scannen'},
  'plt.current': {'zh': '当前装车', 'en': 'Loading', 'de': 'Aktuelle Verladung'},
  'plt.loaded': {'zh': '已装车 {n}', 'en': 'Loaded {n}', 'de': 'Verladen {n}'},
  'plt.pending': {'zh': '待提交 {n}', 'en': 'Pending {n}', 'de': 'Ausstehend {n}'},
  'plt.unitBox': {'zh': '箱', 'en': 'Box', 'de': 'Karton'},
  'plt.unitPallet': {'zh': '托', 'en': 'Pallet', 'de': 'Palette'},
  'plt.plate': {'zh': '车牌', 'en': 'Plate', 'de': 'Kennzeichen'},
  'plt.pickupDate': {'zh': '提货日期', 'en': 'Pickup date', 'de': 'Abholdatum'},
  'plt.notFound': {'zh': '未找到托盘：{code}', 'en': 'Pallet not found: {code}', 'de': 'Palette nicht gefunden: {code}'},
  'plt.ambiguous': {'zh': '车牌对应多个托盘，已加载 {code}', 'en': 'Plate matches several pallets, loaded {code}', 'de': 'Mehrere Paletten, geladen: {code}'},
  'plt.dupPending': {'zh': '该跟踪号已在待提交列表', 'en': 'Already pending', 'de': 'Bereits ausstehend'},
  'plt.dupServer': {'zh': '该跟踪号已装车', 'en': 'Already loaded', 'de': 'Bereits verladen'},
  'plt.queued': {'zh': '已加入队列 {code}', 'en': 'Queued {code}', 'de': 'Eingereiht {code}'},
  'plt.saved': {'zh': '已装车 {code}', 'en': 'Loaded {code}', 'de': 'Verladen {code}'},
  'plt.flushError': {'zh': '提交失败：{msg}', 'en': 'Submit failed: {msg}', 'de': 'Übertragung fehlgeschlagen: {msg}'},
  'plt.queueStopped': {
    'zh': '队列已暂停：请处理出错的跟踪号（重试或删除）',
    'en': 'Queue paused: fix the failed tracking number (retry or remove)',
    'de': 'Warteschlange pausiert: Fehler beheben (erneut oder entfernen)'
  },
  'plt.offlineQueued': {
    'zh': '无网络，已保存在本机，恢复网络后自动提交',
    'en': 'Offline – saved on device, will submit when back online',
    'de': 'Offline – lokal gespeichert, wird später übertragen'
  },
  'plt.retryAll': {'zh': '重试提交', 'en': 'Retry submit', 'de': 'Erneut übertragen'},
  'plt.pendingList': {'zh': '待提交', 'en': 'Pending', 'de': 'Ausstehend'},
  'plt.serverList': {'zh': '已装车列表', 'en': 'Loaded parcels', 'de': 'Verladene Pakete'},
  'plt.remove': {'zh': '移除', 'en': 'Remove', 'de': 'Entfernen'},
  'plt.removeConfirm': {'zh': '从托盘移除 {code}？', 'en': 'Remove {code} from the pallet?', 'de': '{code} von der Palette entfernen?'},
  'plt.removePending': {'zh': '删除待提交 {code}？', 'en': 'Drop pending {code}?', 'de': 'Ausstehende {code} verwerfen?'},
  'plt.switchConfirm': {
    'zh': '还有 {n} 个跟踪号未提交，切换托盘会保留它们在原托盘队列中。继续？',
    'en': '{n} scans are still pending; they stay queued for the current pallet. Switch?',
    'de': '{n} Scans ausstehend; sie bleiben für die aktuelle Palette gespeichert. Wechseln?'
  },
  'plt.close': {'zh': '结束本托盘', 'en': 'Close pallet', 'de': 'Palette schließen'},
  'plt.resolve.resolved': {'zh': '已匹配', 'en': 'Matched', 'de': 'Zugeordnet'},
  'plt.resolve.pending': {'zh': '匹配中', 'en': 'Matching', 'de': 'Wird zugeordnet'},
  'plt.resolve.not_found': {'zh': '未匹配订单', 'en': 'No order', 'de': 'Kein Auftrag'},
  'plt.resolve.error': {'zh': '匹配错误', 'en': 'Error', 'de': 'Fehler'},
  'plt.resolve.unknown': {'zh': '未知', 'en': 'Unknown', 'de': 'Unbekannt'},
  'plt.importantNote': {'zh': '重要提示', 'en': 'Important', 'de': 'Wichtig'},

  // ---------- stock ----------
  'stk.scan': {'zh': '扫描库位码 / 商品条码 / SKU', 'en': 'Scan location / barcode / SKU', 'de': 'Lagerplatz / Barcode / SKU scannen'},
  'stk.location': {'zh': '库位 {name}', 'en': 'Location {name}', 'de': 'Lagerplatz {name}'},
  'stk.item': {'zh': '商品 {sku}', 'en': 'Item {sku}', 'de': 'Artikel {sku}'},
  'stk.search': {'zh': '搜索 "{q}"', 'en': 'Search "{q}"', 'de': 'Suche "{q}"'},
  'stk.rows': {'zh': '库存明细', 'en': 'Stock rows', 'de': 'Bestandszeilen'},
  'stk.sum': {'zh': '合计 {n}', 'en': 'Total {n}', 'de': 'Summe {n}'},
  'stk.available': {'zh': '可用 {n}', 'en': 'Available {n}', 'de': 'Verfügbar {n}'},
  'stk.locked': {'zh': '锁定 {n}', 'en': 'Locked {n}', 'de': 'Gesperrt {n}'},
  'stk.barcode': {'zh': '条码', 'en': 'Barcode', 'de': 'Barcode'},
  'stk.weight': {'zh': '重量', 'en': 'Weight', 'de': 'Gewicht'},
  'stk.zone': {'zh': '库区', 'en': 'Zone', 'de': 'Zone'},
  'stk.loadMore': {'zh': '加载更多', 'en': 'Load more', 'de': 'Mehr laden'},
  'stk.st0': {'zh': '无效', 'en': 'Invalid', 'de': 'Ungültig'},
  'stk.st2': {'zh': '残损', 'en': 'Damaged', 'de': 'Beschädigt'},
  'stk.st5': {'zh': '收货中', 'en': 'Receiving', 'de': 'Im Eingang'},
  'stk.st10': {'zh': '正常', 'en': 'Valid', 'de': 'Gültig'},

  // ---------- pick guide ----------
  'pick.scanList': {'zh': '扫描拣货单号', 'en': 'Scan picklist no.', 'de': 'Pickliste scannen'},
  'pick.scanItem': {'zh': '到库位后扫描商品', 'en': 'At the location, scan the item', 'de': 'Am Lagerplatz Artikel scannen'},
  'pick.next': {'zh': '下一个库位', 'en': 'Next location', 'de': 'Nächster Lagerplatz'},
  'pick.progress': {'zh': '已拣 {a}/{b}', 'en': 'Picked {a}/{b}', 'de': 'Gepickt {a}/{b}'},
  'pick.done': {'zh': '本拣货单已全部核对完成', 'en': 'All lines checked', 'de': 'Alle Positionen geprüft'},
  'pick.notInList': {'zh': '{sku} 不在本拣货单中', 'en': '{sku} is not on this picklist', 'de': '{sku} nicht auf der Pickliste'},
  'pick.lineDone': {'zh': '{sku} 本行已拣满', 'en': '{sku} line already complete', 'de': '{sku} bereits vollständig'},
  'pick.picked': {'zh': '已拣 {sku} @ {loc}', 'en': 'Picked {sku} @ {loc}', 'de': 'Gepickt {sku} @ {loc}'},
  'pick.wrongLocation': {
    'zh': '注意：{sku} 应在 {loc} 拣取',
    'en': 'Note: {sku} should be picked at {loc}',
    'de': 'Hinweis: {sku} gehört zu {loc}'
  },
  'pick.localOnly': {
    'zh': '仅用于现场核对，不回写系统；正式拣货/打包仍在打包台完成。',
    'en': 'For on-floor checking only – nothing is written back; packing stays at the pack station.',
    'de': 'Nur zur Kontrolle – keine Rückmeldung ans System; Packen am Packplatz.'
  },
  'pick.canceled': {'zh': '该拣货单已取消', 'en': 'This picklist was cancelled', 'de': 'Pickliste storniert'},
  'pick.reset': {'zh': '重置核对进度', 'en': 'Reset progress', 'de': 'Fortschritt zurücksetzen'},
  'pick.undo': {'zh': '撤销', 'en': 'Undo', 'de': 'Rückgängig'},

  // ---------- history ----------
  'his.empty': {'zh': '还没有扫描记录', 'en': 'No scans yet', 'de': 'Noch keine Scans'},
  'his.clearConfirm': {'zh': '清空本机扫描记录？', 'en': 'Clear the history on this device?', 'de': 'Verlauf auf diesem Gerät löschen?'},
  'his.ok': {'zh': '成功', 'en': 'OK', 'de': 'OK'},
  'his.warn': {'zh': '提醒', 'en': 'Warning', 'de': 'Warnung'},
  'his.error': {'zh': '失败', 'en': 'Failed', 'de': 'Fehler'},
  'his.unknown': {'zh': '结果未知', 'en': 'Unknown', 'de': 'Unklar'},
  'his.queued': {'zh': '排队中', 'en': 'Queued', 'de': 'Eingereiht'},

  // ---------- settings ----------
  'set.language': {'zh': '语言', 'en': 'Language', 'de': 'Sprache'},
  'set.server': {'zh': '服务器地址', 'en': 'Server URL', 'de': 'Server-URL'},
  'set.origin': {'zh': 'Origin（跨域白名单域名）', 'en': 'Origin (allow-listed web domain)', 'de': 'Origin (freigegebene Domain)'},
  'set.scanner': {'zh': '扫描头', 'en': 'Scanner', 'de': 'Scanner'},
  'set.scannerMode': {'zh': '广播模式', 'en': 'Broadcast mode', 'de': 'Broadcast-Modus'},
  'set.scannerAuto': {'zh': '自动（兼容主流品牌）', 'en': 'Auto (all common brands)', 'de': 'Automatisch (gängige Marken)'},
  'set.scannerNone': {'zh': '关闭广播', 'en': 'Off', 'de': 'Aus'},
  'set.scannerCustom': {'zh': '仅自定义', 'en': 'Custom only', 'de': 'Nur benutzerdefiniert'},
  'set.customAction': {'zh': '自定义广播 Action', 'en': 'Custom broadcast action', 'de': 'Eigene Broadcast-Action'},
  'set.customExtra': {'zh': '自定义数据 Extra 键', 'en': 'Custom extra key', 'de': 'Eigener Extra-Schlüssel'},
  'set.wedge': {'zh': '键盘模式扫描（以回车结尾）', 'en': 'Keyboard-wedge scanning (Enter suffix)', 'de': 'Tastatur-Modus (mit Enter)'},
  'set.test': {'zh': '扫描测试：请扫任意条码', 'en': 'Scanner test: scan any barcode', 'de': 'Scannertest: beliebigen Code scannen'},
  'set.testResult': {'zh': '收到：{code}', 'en': 'Received: {code}', 'de': 'Empfangen: {code}'},
  'set.feedback': {'zh': '提示', 'en': 'Feedback', 'de': 'Rückmeldung'},
  'set.sound': {'zh': '提示音', 'en': 'Sound', 'de': 'Ton'},
  'set.vibrate': {'zh': '震动', 'en': 'Vibration', 'de': 'Vibration'},
  'set.keepScreenOn': {'zh': '屏幕常亮', 'en': 'Keep screen on', 'de': 'Bildschirm anlassen'},
  'set.network': {'zh': '网络', 'en': 'Network', 'de': 'Netzwerk'},
  'set.connectTimeout': {'zh': '连接超时（秒）', 'en': 'Connect timeout (s)', 'de': 'Verbindungs-Timeout (s)'},
  'set.receiveTimeout': {'zh': '响应超时（秒）', 'en': 'Response timeout (s)', 'de': 'Antwort-Timeout (s)'},
  'set.about': {'zh': '关于', 'en': 'About', 'de': 'Info'},
  'set.device': {'zh': '设备', 'en': 'Device', 'de': 'Gerät'},
  'set.version': {'zh': '版本', 'en': 'Version', 'de': 'Version'},
  'set.testBeep': {'zh': '测试提示音', 'en': 'Test sound', 'de': 'Ton testen'},
  'set.serverChangedRelogin': {'zh': '服务器已更改，请重新登录', 'en': 'Server changed – please sign in again', 'de': 'Server geändert – bitte neu anmelden'},
  'set.latency': {'zh': '延迟 {ms} ms', 'en': 'Latency {ms} ms', 'de': 'Latenz {ms} ms'},
  'set.checkNow': {'zh': '检测网络', 'en': 'Check network', 'de': 'Netz prüfen'},
};
