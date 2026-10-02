# MICLinker PDA（Flutter）

MICLinker 海外仓的原生 PDA App，直接调用现有 Go 后端（`/v0/*`）和 CarrierGate。**后端不需要任何改动。**

- 目标设备：**iData 95W（Android 6.0）**，支持 Android 5.0+（minSdk 21），只打包 armeabi-v7a 和 arm64-v8a
- 界面、菜单名、提示语与 erp.webapp 保持一致（Element UI 风格），**默认英文**，可切换中文和德语
- 翻译直接取自 `erp.webapp/src/locale`（见 `tool/sync_web_locale.py`），与网页端用词完全一致

## 模块（与网页端菜单同名）

| 模块 | 对应网页端 | 说明 |
|---|---|---|
| **Picklist** | Picklist / Picking Scan / Pack Scan Order | 列出待处理拣料单，扫码或点选进入：<br>• 类型 100 → **Pick Scan Batch**（= `packScanBatch.vue`）<br>• 类型 1 → **Pack Scan Order**（= `packScan.vue`） |
| **Shipping Scan** | shippingScan.vue | 出库复核，SKU QC，SN |
| **Loading Scan** | palletHandover.vue | 扫车牌或托盘码，再扫跟踪号；断网时先存在本机，恢复后自动提交 |
| **Logging Scan** | loggingScan.vue | |
| **SN Scan** | snScan.vue | 每个码扫两次确认，新 SN 通过 socket.io 发到打印站 |
| **RMA** | RMA（received.vue） | 扫退货包裹，新建或打开 RMA，扫商品，拍照，然后入库 |
| **Inventory** | Inventory / Compartment | 扫库位、商品或批次，只读查询 |
| Scan History / Settings | — | PDA 专用 |

已移除：未完工的 Receiving Scan，以及上一版的只读「拣货指引」。

### Picklist（会真实改变拣料单状态）

与网页端写入的数据完全一致：

1. 扫商品 → 输入数量和包装材料（Pick Scan Batch），或按订单扫齐商品（Pack Scan Order）
2. 向 CarrierGate 申请面单：
   - Batch：`batchPrintLabel`
   - Order：`printShipmentLabelAtScan`，接口地址从 Mask `oms.outbound.list` 读取
3. `PUT /v0/p11y/pick/`，回写 `itemInfo.qtyPrinted`、`itemQtyPicked`、`printBatch` / `ordersFin`
   - 后端在全部拣完时自动把状态改为 **Packing Completed（20）**
4. 下载面单 PDF，发送到打印站的 **PrintBridge**

完成后页面显示「Well Done」和 **Next Picklist** 按钮。

Pick Scan Batch 的面单索引（`lblIdx`）计算逻辑，已用网页端原始 JS 做过 500 组随机数据的差分测试，结果一致。

**必须先配置打印站**，否则不会申请面单：设置 → Print station → 填入装有 PrintBridge 的电脑 IP（默认端口 9100），再从列表中选择打印机。PrintBridge 即 `~/projects/PrintBridge`，网页端「DHL Printer」用的也是它。

Pack Scan Order 中这些操作仍需在电脑端完成：没有运单的订单「Request Shipment Label」，以及 ADR / CMR / 报关单打印。PDA 上会给出提示。

### RMA（替代未完工的 Receiving Scan）

1. 扫包裹单号
   - 已存在 RMA 的 → 直接打开
   - 不存在的 → 新建，并按原订单自动带出 Reference No. 和客户
2. 扫商品（自动累加数量），设置每行状态（Valid / Damaged / Invalid / Unchecked / Scrapped）、类型、包裹状态、备注，可以拍照
3. 保存（新建用 `POST`，修改用 `PUT /v0/r7greceiving/`）
4. **Inbound**：扫一个库位会填给所有未设置库位的行；先点选某一行再扫库位，则只设置该行
   - 确认后调用 `POST /v0/r7greceiving/inbound`，后端入库并把状态改为 Inbounded（100）
   - 如果超时，会先回读该 RMA 的状态再决定是否需要重试，**绝不盲目重发入库请求**

## iData 95W 扫描头设置

推荐使用**广播模式**：系统「扫描设置 / iScan」→ 输出方式选「广播」。

- 默认 Action 是 `android.intent.action.SCANRESULT`，Extra 是 `value`
- App 的「自动」模式已包含这个配置，无需修改
- 也可以用「键盘模式」，但需要在扫描设置里开启回车后缀

App 的「设置」页最上方有扫描测试区，扫任意条码即可确认扫描头已接通。

95W 有实体数字键盘：键盘模式下只有快速连续输入且不少于 3 个字符的内容才会被当作扫描，手动按数字键不会误触发。

## 弱网设计（与上一版相同）

- 扫描类接口多数**不是幂等的**，只在确认请求没有发出去时才自动重试
- 超时时界面显示「结果未知」，并回读服务器数据核对
- 拣料单和 RMA 的 `PUT` 写入的是绝对值，可以安全重发
- Loading Scan 的扫描先进入本机持久化队列，断网后恢复会自动提交
- 登录过期时在当前页弹出重新登录对话框，正在进行的任务不会丢

## 构建

**必须使用 Flutter 3.32.x。** Flutter 3.35 及以后的版本只能构建 Android 7.0+ 的 APK。

```bash
~/fvm/versions/3.32.8/bin/flutter build apk --release --target-platform android-arm,android-arm64
```

版本号在 `pubspec.yaml`（当前为 `0.0.2+2`）和 `lib/pages/settings_page.dart` 的 `appVersion` 中，修改时两处要一致。

签名使用 `android/key.properties` 和 `android/app/mic-pda-release.jks`，两者已加入 `.gitignore`，**请务必备份**。之后的每次升级都必须用同一个密钥签名，否则无法覆盖安装。

## 测试

```bash
~/fvm/versions/3.32.8/bin/flutter test
```

共 16 项，覆盖：
- 失败分类（不该重试的不重试）
- 扫描分发和防抖
- 三种语言的翻译是否齐全
- 网页端用词
- Pick Scan Batch 与网页端 JS 的差分测试（需要 node）
- composeCarrierConfig

修改过网页端 key 后，需要先运行 `python3 tool/sync_web_locale.py` 更新翻译。

### 本地模拟后端（不碰生产数据）

```bash
~/fvm/versions/3.32.8/bin/dart run tool/mock_server.dart 8787
```

- 同时启动 API 和 CarrierGate（:8787），以及 PrintBridge 模拟（:9100）
- 模拟器设置：
  - 服务器填 `http://10.0.2.2:8787`
  - 打印站填 `10.0.2.2`
- 模拟账号：`pda@mock.local` / `mock-pass`，验证码 `1234`
- 测试数据：
  - 拣料单 `PL20260001`（Batch）、`PL20260002`（Order）
  - RMA `RET0001`
  - 托盘 `LD20260001`
  - 库位 `A-01-01`
  - 商品条码 `4006381333931` / `4006381333948` / `6970000000011`
- 弱网模拟：
  - `GET /__mock/delay?ms=30000`：所有响应延迟（制造超时）
  - `GET /__mock/offline?sec=20`：一段时间内拒绝所有连接（模拟信号死角）
- 用 adb 模拟 iData 扫描：

```bash
adb shell am broadcast -a android.intent.action.SCANRESULT --es value PL20260001
```

## 部署

1. 用 `adb install -r release/MIC-PDA-0.0.2.apk` 安装，或把 APK 拷贝到 PDA 上安装。签名与上一版相同，可以直接覆盖升级。
2. 首次登录需要验证码，之后这台设备会被信任（eid），不再需要验证码。
3. 在「设置」中配置打印站，并扫码确认扫描头可用。
