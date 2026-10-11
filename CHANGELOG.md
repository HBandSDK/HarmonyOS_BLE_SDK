# 变更记录

## 1.2.8 — 2026-10-11

自定义背景「时间位置」口径声明(真机验收反馈)。无 API/行为变更,仅文档与注释。

### 说明

- **时间位置可用值与屏形相关**（对齐 iOS 屏形判定,真机验收确认）:
  - 圆形屏 / 带屏（窄长方屏,主图高/宽 >1.4,如 200×320/172×320/80×160）仅支持
    1=上 2=中 3=下;
  - 方屏 / 矩形屏（高/宽 ≤1.4）才支持 4=左上 5=右上 6=左下 7=右下。
  屏形用 `getPhotoDialSizeConfig(customDialType)` 查表（`isCircle` + `mainWidth/Height`）判定。
  已同步 `CustomBgDialParams`/`PhotoDialInfo` 注释、API.md 字段表与示例工程提示文案。

## 1.2.7 — 2026-10-11

照片表盘能力补全：机型尺寸表下沉 SDK、圆形表盘小图铺黑底、中科照片表盘编码/拼包 helper,
示例工程接入裁剪页并补中科传输卡。向后兼容,均为新增 API。

### 新增

- **机型尺寸表下沉 SDK**:`dialService.getPhotoDialSizeConfig(customDialType)`(及免连接的
  `findPhotoDialSize()`)按设备上报的自定义表盘类型查内置全量尺寸表(主图/小图画布/小图
  照片区/是否圆形,与参考实现同源提取)。第三方没有这张表就无法正确给定
  `convertDialPhotoToBmp` 的目标尺寸;表外类型返回 null 回退屏幕尺寸。
- **`convertDialPhotoToBmp` 新增 `padBlack` 参数**:把透明像素改写为不透明纯黑——圆形表盘
  小图需纯黑底(iOS 端 2025-05 设备 bug 兼容口径),配合宿主裁剪出的椭圆透明 PNG 使用。
- **中科照片表盘 helper 下沉**:`convertZKPhotoImageToPar(uri, w, h, isZK569x)`(图片→通道
  编码,内部完成 RGBA 解码 + 随包序列化库编码)与 `buildZKPhotoDialPayload(bg, pre)`(主图
  在前拼整包,段长小端)。此前拼包范式只在宿主参考实现里,第三方无从得知。

### 示例工程

- **接入裁剪页**:选照片后进入按机型比例取景的裁剪页(工程内自带裁剪组件,圆形表盘椭圆
  取景框、输出保留透明区的 PNG),裁剪结果回表盘页传输。
- **照片表盘卡重做**:新增「按机型查尺寸」(读设备类型→查表回填主图/小图尺寸+圆形标志);
  小图按画布尺寸传输,圆形表盘自动铺黑底。
- **新增中科照片表盘卡**:共用照片与尺寸,569 系列开关,完整演示 编码→拼包→传输;
  569 方屏圆角裁剪未做(宿主按机型规格自加)。

## 1.2.6 — 2026-10-11

照片表盘三端核对(iOS 黄金实现 + 主工程真机修复)后的对齐修复。向后兼容,
`transferCustomBgDial/Pair` 签名不变。

### 修复

- **照片背景传输前自动切回出厂照片槽**（best-effort）:若上一步传过市场
  表盘,当前表盘是市场文件;不切回则传输完成后的背景绑定会落到市场表盘上,
  切屏到照片槽后内容不符,设备回退"本地表盘2"（真机实证）。
  iOS 无此步（其激活命令语义含切换）,鸿蒙侧必须先切。预切换全程 10s 超时上限、
  失败仅记日志不阻断传输;`transferCustomBgDial` 与 `transferCustomBgDialPair` 均生效。
- **`transferCustomBgDial`（单图）补 RCSP 就绪门控**:RCSP 会话未就绪时直接 FAIL
  回调并给出原因,不再静默无回调卡死（与 `transferCustomBgDialPair`/
  `transferMarketDial` 对齐）。
- **`setCustomBackground` 校验设备响应确认字节**:非成功确认时返回失败及原因
  （对齐 iOS 判定口径;中科流程以该回包作为整个传输的完成依据）。
  响应异常不改变既有容错语义。
- **表盘信息读取响应守卫修正**:类型回显不匹配 或 ack≠1 任一成立即判无效响应
  （原逻辑照抄 iOS 源码的 `&&`,疑似笔误——设备 NAK 时会把失败帧残余字节当数据解码）。

### 说明（示例工程）

- 照片表盘卡片说明补充:小图为含边框画布图（尺寸机型特定,如主图 410×502、
  小图画布 256×308 的机型）,圆屏机型小图需铺纯黑底（设备端兼容）,
  请按机型规格表填写尺寸,设备上报屏幕尺寸仅作缺省。

## 1.2.5 — 2026-10-11

表盘传输排查增强。向后兼容,无行为变更。

### 新增

- **`deleteDownloadedMarketDial` 删除前输出设备表盘清单快照**（文件名+uuid 全量）,
  并在任务间隙结束时输出标记——用于核对"删除→传输"时序中市场槽的真实状态。
- **示例工程表盘页新增「排查日志」面板**：经 `Logger.setSink` 实时收取本页期间的
  SDK 日志（删除清单、传输文件名、设备错误码等,最新在上）。传输失败时展开面板
  截图即可定位,无需抓取系统日志。

### 修复（示例工程）

- **表盘二进制改用普通字段持有**:`@State` 持有 `ArrayBuffer` 时,状态管理包装
  失败,后续任何读取都会抛 `TypeError "don't have internal slot"`（ArkUI
  stateMgmt getter）——此前示例工程所有"slot"报错均源于此,并非设备拒收。
  二进制现由普通属性持有,UI 仅观察基础类型状态。
- **移除排查期逐行打点日志**:市场表盘传输链路确认打通后,清理临时诊断
  console 输出(页面构建指纹、删除/传输各阶段打点、异常堆栈/JSON 转储)。
  错误路径各保留一条 `console.error`;「排查日志」面板与 SDK 侧删除清单
  日志为正式特性,予以保留。

## 1.2.4 — 2026-10-11

市场表盘"删除旧表盘 → 立即传输新表盘"时序修复。向后兼容。

### 修复

- **删除旧市场表盘后增加 500ms 任务间隙**：设备侧删除任务的关闭回包可能晚于
  `deleteDial` 的 Promise 完成（真机日志确认）。紧贴删除立即发起新表盘传输，
  传输请求会被仍在关闭中的任务通道吞掉——表现为无进度、无回调、无失败提示。
  宿主参考实现里删除与传输之间隔着网络下载（天然留出间隙），SDK 现显式等待
  等价间隙。此前 demo"先下载后删除再立即传输"的紧凑时序因此全部静默失败。
- **`transferMarketDial` 入口防护**：RCSP 通道状态读取若抛异常，现转为 FAIL
  回调并记录日志，不再静默中断；算子为空的早退路径补充日志。
- **示例工程错误归属修正**：传输阶段异常不再误报为"下载失败"，单独提示
  "传输异常/传输启动异常"，并补充各阶段日志便于现场排查。

## 1.2.3 — 2026-10-10

市场表盘网络目录能力下沉 SDK:表盘目录拉取与 .bin 下载封装为 `dialService` API,
demo 补全"网络列表 → 下载 → 传输"完整闭环。向后兼容,仅新增 API。

### 新增

- **`dialService.fetchNetworkDialList()`**:分页拉取网络市场表盘目录(纯 HTTP,
  不需要设备连接)。入参 `dialShape` / `binProtocol` / `maxLength` 来自
  `readMarketDial()` 的返回;`deviceVersion` 缺省时自动取当前连接设备。
  请求失败不抛异常,返回 `success=false` + `errorMessage`。
- **`dialService.downloadNetworkDialFile()`**:按目录项 `fileUrl` 下载表盘 `.bin`,
  产物直接可传 `transferMarketDial` / `transferZKMarketDial`。
- **门面导出类型**:`NetworkDialItem` / `NetworkDialListParams` /
  `NetworkDialListResult` / `NetworkDialDownloadResult`。
- **demo 表盘页新增「网络市场表盘」卡**:自动复用已读取的市场表盘信息拉目录
  (未读过则现读)、分页加载、点击条目自动下载并走市场表盘传输通道(带进度),
  与「市场表盘传输」「设备表盘文件」卡形成完整闭环。
- **`dialService.deleteDownloadedMarketDial()`**:删除设备上已下载的市场表盘
  (市场表盘槽,uuid 固定)。杰理设备只保留一个已下载市场表盘槽,槽被占用时
  `transferMarketDial` 会被设备拒收(报 "don't have internal slot")——传输前
  必须先删除。对齐宿主参考实现的传输前删除时序。
- **demo 传输时序对齐**:杰理传输前调用上述删除;传输成功后补
  `setCustomUIStyle(1, UIStyleType.CUSTOM)` 切换屏显到市场表盘。
- **修正文档/模型中 `DeviceDialFile.uuid` 的说明**:实际值为 GUID 形式
  (出厂 0000…/照片 1111…/市场 2222…),非 0/1/2。

## 1.2.2 — 2026-10-10

表盘交付能力补全:新增照片表盘图片一站式转换 API,demo 补齐市场表盘/照片表盘/设备
表盘文件三块演示。向后兼容,仅新增 API。

### 新增

- **`dialService.convertDialPhotoToBmp()`**:图片 URI → 按目标尺寸解码缩放 → PNG →
  设备芯片 BMP → `ArrayBuffer`,产物直接可传 `transferCustomBgDial` /
  `transferCustomBgDialPair`。芯片型号缺省时自动 `getCustomBgChipType()`;内部含
  20s 超时保护(位图编码偶发无回调路径,防 await 永悬)。此前宿主需自行
  组合 ImageKit + 杰理位图库——后者虽随 SDK 附带但属内部依赖,现经本 API 封装,
  宿主不再直接 import。
- **门面导出 `JL_Chip` 枚举与 `DialPhotoBmpResult` / `DialScreenSize` 类型**:
  `JL_Chip` 是 `getCustomBgChipType()` 的既有公开返回类型,此前未 re-export,宿主无法
  具名引用;现从门面导出(bmpconvert 仍由 SDK 内部 libs/ 自包含,消费方依赖声明不变)。
- **demo 表盘页补全**(`DialPage`):新增市场表盘传输(选择 .bin,按 `hasJlRcspService()`
  自动分流 `transferMarketDial` / `transferZKMarketDial`,带进度)、照片表盘传输
  (选择照片 → 双图 BMP 转换 → `transferCustomBgDialPair`,成功后自动切屏到照片表盘槽
  并设置时间元素)、设备表盘文件管理(列表/当前表盘/切换/删除)、UI_STYLE_CHANGED
  设备端推送展示。

## 1.2.1 — 2026-10-10

ECG 测量结束链路修复:设备在 100% 后上报的"测试结束"与"测试失败"包此前被静默丢弃,
上层只认诊断结果——设备无诊断报告时,测量会永远停在"进行中"。同时纠正诊断结果
授权门控的执行点。向后兼容,仅新增枚举成员与事件。

### 修复

- **`EcgService` 新增 `FAILED` / `OVER` 推送事件**(设备上报的测试失败 / 测试结束包,
  对应 `EcgDataType.FAILED`(3) / `OVER`(4),`data` 为 `null`):上层收到后应结束测量
  流程,并主动调 `stopMeasurement()` 结束本次测试。
- **`RESULT` 事件始终下发,疾病诊断授权门控只作用于疾病字段**:此前未授权时整个
  诊断结果被丢弃(连心率 / 呼吸率 / HRV / QTc 等基础生理指标一起)。现对齐门控语义:
  基础生理指标不受控、始终下发;未授权时疾病诊断字段(`diagnosticData` / `riskInfo` /
  `qrsTime` / `qrsAmp` / `pwvMean` / `stMean` / `sdnn` / `rmssd`)置 **0**。
  **离线历史 `getHistory()` 同语义**:未授权时上述疾病字段同样置 0,测量时间 /
  秒数 / 平均基础指标 / 逐秒波形不受控。

## 1.2.0 — 2026-10-09

新增 PTT(脉搏波传导时间)测量与杰理 OTA 固件升级完整支持,并修复一批闹钟/运动/皮电数据解析问题。

### ⚠️ 破坏性变更(2 处)

- **`HealthGlanceType`(微体检)枚举位值重排**:成员名不变,数值全部变化。
  迁移:一律以成员名引用(如 `HealthGlanceType.HRV`),**不要持久化或比对原始数值**;
  已持久化旧数值的需按旧表映射一次。
- **`SportModeCrc` 字段改名**:`crc0/crc1/crc2` → `crcList: number[]`。
  GPS 设备最多 5 条、非 GPS 设备最多 3 条,空槽已过滤。
  迁移:`r.data.crc0` → `r.data.crcList[0]`,或遍历 `crcList`。

其余改动均向后兼容。

### 新增

- **`PttService`(PTT 脉搏波传导时间)**:支持「设备驱动」与「App 主动」两种测量模式,
  实时波形、每秒心率 / QT / HRV、测量完成结果,及导联脱落 / 设备忙 / 设备结束等推送事件。
- **设备 PTT 模式状态**:`VPDevice.pttState` 字段 + `SDKEventType.PTT_STATE_CHANGE` 事件 +
  `PttService.onEnterPttTest`(进入 / 退出 PTT 模式),可驱动首页入口图标显隐等 UI。
- 特性位新增 `pttFunction`(设备是否支持 PTT)。
- **杰理 OTA 升级完整支持**:`OtaService.startJlOta()` 现返回真实的异步成败(修复旧版发完即报
  "成功"的问题),新增 `enterOta()` 前置入口与 `OtaStepCallback` 结构化步骤事件
  (开始 / 回连 / 完成 / 取消 / 错误等);固件传输后设备重启进 DFU 的**回连由 SDK 内部自动接管**
  (DFU 地址自动计算 + 3 次重试),并提供 120s 智能超时(有进度自动续期)防永久等待。
- **`OtaUpgradeState`**:全局"OTA 进行中"标志,宿主 App 在 OTA 期间应据此屏蔽自身重连逻辑。
- `AutoMeasureFeature.FALL_DETECTION = 9`(跌倒检测),不再需要业务侧写裸值。
- `SkinElectricData` 新增 `status` 字段:0=正常、2=低电、4=未佩戴、5=检测失败、其它=设备忙。

### 修复

- **文字闹钟**:下发后等待设备应答并校验,失败自动重发一次——修复"App 显示成功、设备未生效";
  本地缓存为空时自动补读全表,避免因校验值失真被设备静默拒绝;修正读取进度与列表解析错位。
- **运动数据**:海拔与 GPS 经纬度按有符号数解析,修复负海拔 / 西经南纬显示为天文数字;
  无屏 GPS 手表的轨迹点不再丢失;GPS 判定改为按单条运动的实际类型。
- **皮电(GSR)**:测量结束的确认包不再被误当作数据 / 错误处理。
- **连接**:`getConnectDeviceRssi()` 在链路未就绪时不再同步抛异常导致崩溃。
- **OTA 回连**:回连后内部写通道正确重绑,修复回连后所有命令写失败(错误码 2901003)。

### 交付面

- 示例工程运动页适配 `SportModeCrc.crcList` 新字段。

### 说明

- 混淆仍未开启(同 1.0.0 / 1.1.0):公开符号名未混淆,待公开面稳定后再启用。

## 1.1.0 — 2026-09-12

新增微体检与女性生理周期两个领域服务(共 31 个),日志可引流进宿主自身日志系统,
并修复了一批连接/重连稳定性问题与数据解析问题。

### ⚠️ 破坏性变更(仅 1 处)

- **`EcgSavedIdResult.id`(`number`)→ `ids`(`number[]`)**:设备单次回包可返回多条测量 ID,
  原单值字段无法承载。迁移:`r.id` → `r.ids?.[0]`,或遍历 `r.ids` 取全部。

其余改动均向后兼容。

### 新增

- **`HealthGlanceService`(微体检)**:一次测量采集多项体征。`isSupported()` /
  `startMeasurement()` / `stopMeasurement()`,配进度、完成、错误三个监听。
- **`WomenService`(女性生理周期)**:五种状态(无状态/月经/备孕/怀孕/妈咪)的设置与读取,
  不同状态必填的日期不同。
- **`LogSink`**:经 `Logger.setSink()` 把 SDK 日志引流进宿主自身的日志系统,
  可同时关闭 SDK 自带的落盘与 hilog,实现单一统一日志文件。用法见 [INTEGRATION §10.1](docs/INTEGRATION.md)。
- **`VPBleSDK.isNativeLinkUp()`**:区分「链路尚未建立」与「链路已建立、正在初始化」,
  供上层重连策略决策(`getState()` 在整个 BINDING 阶段不变,无法区分二者)。
- **`VPBleSDK.setConnectionConfirmation(isNeed)`**:控制设备端是否弹出连接确认框。
- **`VPBleSDK.getConnectDeviceRssi(cb)`**:读取当前连接的信号强度。
- `ContactService.save()` 新增可选入参 `supportSos`(默认 `true`,旧调用方无需改动):
  传 `false` 时不下发 SOS 数据块,用于不支持 SOS 的机型。
- 血压结果新增 `privateMode`(私人模式)字段。
- 新增错误码 `SDKErrorCode.ENGINE_DESTROYED`。

### 修复

- **连接 / 重连稳定性**:清理断连后残留的请求状态与定时器,消除其对重连后指令下发的干扰;
  修复 MTU 协商阶段的空引用与回调竞态;链路已断时请求不再无效重试到超时。
- **数据解析**:修复血糖数值、ECG 记录 ID 列表、运动轨迹采样点、设备开关配置读取等多处
  解析问题;改善表盘与功能模块在不同机型上的数据下发兼容性。
- **HRV 分析**:散点图、洛伦兹星级与相似度的计算口径及生成门槛已与 iOS / Android 端对齐,
  同一设备同一份数据在三端结果一致。

### 交付面

- 补齐微体检相关类型的公开导出(1.0.0 遗漏,集成方此前拿得到实例却无法命名其类型与枚举)。
- 示例工程新增微体检、女性生理周期两页(共 36 页)。

### 说明

- 混淆仍未开启(同 1.0.0):公开符号名未混淆,后续版本计划开启。

## 1.0.0 — 2026-07-23

VPBleSDK for HarmonyOS 首个第三方交付版本。

### 交付内容
- VPBleSDK HAR:`VPBleSDK` 单例 + 29 领域服务 + RCSP 桥接 + HRV 分析器 + 完整数据模型。
- 6 个杰理(JieLi)HAR 随包:RCSP / OTA / 位图转换 / PAR 序列化。
- 可运行集成示例工程(`sdk-demo/`):扫描 → 连接 → 电量 → 事件。
- 集成文档(QUICKSTART / INTEGRATION / API / PERMISSIONS)。

### 关键集成约定
- 包名/依赖键/import 名统一为 `@veepoo/vpble-sdk`(scoped,防与其他包冲突;ohpm 强制依赖键 == 包内部名)。
- **SDK HAR 自包含**:6 个杰理 HAR 已打入其内部 `libs/`,集成方**只需声明 `"@veepoo/vpble-sdk"` 一个依赖**,ohpm 自动拉取杰理传递依赖。不要额外声明 6 个杰理(会冲突)。
- 蓝牙扫描需定位权限,且扫描由集成方驱动(`ble.startBLEScan` + `processScanResults`)。

### 已知限制 / 后续
- **混淆(首版关闭)**:公开符号名未混淆,后续版本计划开启,待公开面稳定后再启用。
- **公开面**:出货 HAR 的 `.d.ets` 仅保留类型、签名与字段名;协议实现相关的内部组件不纳入公开导出。
- 资源冲突警告:杰理 HAR 自带资源(`page_show`、`shared_desc` 等)可能与集成方同名,警告级,不影响功能。
- ArkTS API 弃用:`router.pushUrl` / `router.back` 在新版 SDK 标记弃用(demo 仍可用),后续可迁 `Navigation`。

### 许可
- VPBleSDK 由 Veepoo 授权集成方使用,以双方协议为准。
- 随包杰理 HAR 为第三方组件,Veepoo 已获其再分发授权,随 SDK 一并提供。
