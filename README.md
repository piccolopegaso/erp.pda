# MIC 仓库 PDA（Flutter）

MICLinker 海外仓的 PDA 原生 App，从 0 开始重写，不再在 Chrome 里运行 erp.webapp。

- 支持 **Android 5.0+**（minSdk 21），已在 **Android 6.0 (API 23)** 模拟器上做过端到端测试
- 只打包 armeabi-v7a 和 arm64-v8a，release APK 约 16 MB
- 界面支持中文、English、Deutsch

## 模块

| 模块 | 对应 Web 页面 | 后端接口 |
|---|---|---|
| 出库扫描（复核 / SKU 质检 / SN） | `warehouse/shippingScan.vue` | `p11yorders/scanShipSN`、`scanItemSKUQC`、`scanItemSN` |
| 装车交接（托盘 / 车牌 → 跟踪号） | `wms/palletHandover.vue` | `wms/pallets/handover/scan`、`{code}/tracking[/flush\|/remove]` |
| 拣货List（只读，按库位顺序核对） | `warehouse/picklist` + `packScanBatch` | `p11y/pick/any`、`p11y/pick/` |
| 扫描登记 | `warehouse/loggingScan.vue` | `p11yorders/scanLog`、`r7gorders/scanLog` |
| 收货/退货 | `warehouse/receivingScan.vue` | `r7greceiving/scan`、`r7greceiving/` |
| SN 换标 + 远程打印 | `warehouse/snScan.vue` | `p11yorders/swapSN` + socket.io `print` |
| 库存查询（库位 / 商品 / 批次） | `wms/inventory`、`wms/compartment` | `compartment/any`、`item/any`、`inventory/list` |
| 扫描记录（本机） | — | — |
| 设置（扫描头 / 声音 / 网络 / 语言） | — | — |

### 没有做进 PDA 的部分

- **盘点 v2**：后端现在报 `Error 1054 (42S22) Unknown column`，说明生产库的表结构和 stocktakev2 代码不一致，属于后端或数据库迁移问题。前端重写解决不了，需要先修好后端。
- **交接签字**：Web 端的流程是上传签字后的 PDF，属于办公桌上的操作。
- **拣货回写 / 打包**：picklist 用的是整对象 `PUT`，在手持端回写风险太高，所以拣货指引只做现场核对，打包仍在打包台完成。
- **一键强制出库**（`oms.orders.requestShipOut` 动态表单）：属于管理操作，没有放进 PDA。

## 关键设计

### 1. 服务器要求 `Origin` 请求头
Go 后端的 `accessControl` 会拒绝不带白名单 Origin 的请求（返回 HTTP 400），而原生 App 默认不带 Origin。
App 默认发送 `Origin: https://miclinker.com`（可在「设置 → Origin」中修改）。如果换了部署域名，记得同步修改。

### 2. 弱网 / 断网
- 很多扫描接口**不是幂等的**：每扫一次，服务器就加 1。所以 App 只在**能确定请求没有发出去**时自动重试（连接失败、DNS 失败、连接被拒绝）。
- 如果超时，服务器可能已经处理了，也可能没有。这时界面显示紫色的「结果未知」卡片，并自动重新读取进度（SKU 质检 / SN / 退货单），**不会**盲目重发。
- 装车扫描会先写入**本机持久化队列**（按托盘分开保存），再逐条提交：
  - 断网时，扫描内容保存在本机，恢复网络后自动提交。
  - 提交前会先拉取服务器上的列表并去重，避免重复提交。
  - 遇到业务错误（例如 `TrackingConflictError`）时队列暂停，操作员可以选择重试或删除这一条，和 Web 端的逻辑一致。
- 拣货指引在拣货单加载后可以离线使用，条码和 SKU 的对应关系也缓存在本机。
- 登录过期时，在当前页面弹出重新登录的对话框，正在进行的任务不会丢。

### 3. 扫描头
- **广播模式**（推荐）：默认「自动」，同时监听优博讯、Honeywell、Zebra DataWedge、iData、东集、新大陆、成为、商米和通用格式的广播。也可以在设置里填写自定义的 Action 和 Extra 键。
- **键盘模式**：扫描头模拟键盘输入并以回车结尾，同样支持。
- 300ms 内重复扫到同一个码会被忽略（防抖）。扫描只会送到当前可见的页面。
- 「设置」页最上方有扫描测试区，可以直接检查扫描头是否已接通。
- 成功、提醒、错误分别用不同的提示音（ToneGenerator）和震动区分，不依赖任何音频插件。

## 构建

**必须使用 Flutter 3.32.x。** Flutter 3.35 及以后的版本只能构建 Android 7.0+（API 24）的 APK。

```bash
~/fvm/versions/3.32.8/bin/flutter build apk --release --target-platform android-arm,android-arm64
```

生成的文件在 `build/app/outputs/flutter-apk/app-release.apk`。

### 签名密钥（重要）
`android/key.properties` 和 `android/app/mic-pda-release.jks` 已加入 `.gitignore`。**请把这两个文件备份到安全的地方。**
以后每次升级 App，都必须用同一个密钥签名，否则 PDA 上无法覆盖安装。

## 测试

```bash
~/fvm/versions/3.32.8/bin/flutter test
```

单元测试覆盖：
- 响应包解析（`code` / `data`）
- 各类失败的分类（不该重试的请求不重试）
- 403 时触发重新登录
- 扫描分发和防抖
- 三种语言的翻译是否齐全

### 本地模拟后端（端到端测试，不碰生产数据）

```bash
~/fvm/versions/3.32.8/bin/dart run tool/mock_server.dart 8787
```

- 模拟器里把服务器地址填成 `http://10.0.2.2:8787`。
- 模拟账号：`pda@mock.local` / `mock-pass`，验证码 `1234`。
- 弱网模拟：
  - `GET /__mock/delay?ms=30000`：所有响应延迟 30 秒（制造超时）
  - `GET /__mock/offline?sec=20`：20 秒内拒绝所有连接（模拟信号死角）
- 用 adb 模拟扫描头广播：

```bash
adb shell am broadcast -a android.intent.ACTION_DECODE_DATA --es barcode_string TRK1001
```

## 部署到 PDA

1. 把 APK 拷贝到 PDA 上安装，或者用 `adb install release/MIC-PDA-1.0.0.apk` 安装。
2. 首次登录需要输入验证码，之后这台设备会被信任（eid），不再需要验证码。
3. 打开「设置」，扫任意条码，确认扫描头已接通。如果没有反应：
   - 在 PDA 系统的扫描设置里把输出方式改为「广播」，或者
   - 在 App 里填写该机型的自定义 Action 和 Extra 键。
