# CXExamAI · 学习通考试答题（iOS / TrollStore）

把安卓 LSPosed 模块 `com.yinshibai.chaoxingx` 的考试答题链路搬到 iOS：**页面里抓题 → 调大模型 → 在页面里回填**。
只做考试相关功能，不碰作业/刷课/签到。

目标 App：学习通 iOS 6.5.3（`com.ssreader.ChaoXingStudy`），最低 iOS 15.6。
运行环境：TrollStore（免越狱），用 TrollFools 把 `CXExamAI.dylib` 注入学习通。
依赖：**零第三方库**，不依赖 CydiaSubstrate、不依赖 Theos。

---

## 一、目录

```
CXExamAI/
├─ src/
│  ├─ CXMain.m        入口（只对学习通生效）
│  ├─ CXWeb.m         WKWebView 捕获 + 脚本注入 + 消息桥
│  ├─ CXAI.m          DeepSeek（OpenAI 兼容）请求与解析
│  ├─ CXHUD.m         悬浮球 / 答案面板 / 设置页 / 截屏穿透容器
│  ├─ CXGuard.m       截屏瞬间隐藏、系统截图监听
│  ├─ CXHook.m        runtime 方法交换
│  ├─ CXCommon.m      日志与配置
│  ├─ CXAssets.m      承载注入用的 JS
│  └─ cx-core.js      页面端：抓题、回填、防切屏检测
└─ .github/workflows/build.yml
```

---

## 二、编译（不用 Mac）

1. 在 GitHub 新建一个**私有仓库**，名字随意，比如 `cxexamai`。
2. 把本文件夹（`CXExamAI`）里的**全部内容**上传到仓库根目录：
   根目录下应该直接看到 `src/`、`.github/`、`README.md`。
   网页上传方式：仓库页 → Add file → Upload files → 把 `src` 文件夹和 `.github` 文件夹一起拖进去 → Commit。
3. 打开仓库的 **Actions** 标签 → 左侧 `build-dylib` → 右侧 `Run workflow` → 绿色按钮。
4. 等 2～4 分钟，构建成功后会自动创建一条 **Release**（标签形如 `v1.0.8`），
   在仓库右侧 Releases 里点进去，下载 `CXExamAI.dylib` 即可。

> 构建产物走 Release 而不是 Artifacts，是因为账号的 Artifacts 存储配额已满（上传会报 quota hit）。
> Release 附件不占该配额，后续每次构建都会生成一个新版本，旧版本可随时删。

---

## 三、注入（手机上）

1. 把 `CXExamAI.dylib` 传到手机（AirDrop / 文件 App / Filza 都行）。
2. 打开 **TrollFools** → 应用列表里选 **学习通** → 注入 → 选 `CXExamAI.dylib`。
3. 注入完成后 TrollFools 会提示重启 App，点重启（或手动上滑杀掉学习通再打开）。

> 你的那台机器已经能加载第三方 dylib（FakeTools 就是证据），TrollFools 这条路是通的。
> 本插件不链接 CydiaSubstrate，注入后不会再要求额外的框架。

---

## 四、首次配置

打开学习通 → 进入任意课程 → 页面上会出现一个半透明小圆球（写着 `AI`）。

- **长按圆球** → 打开设置页：
  - 接口地址：默认 `https://api.deepseek.com`
  - 模型：默认 `deepseek-chat`
  - API Key：填你自己的 DeepSeek Key（`sk-` 开头）
  - 自动答题 / 考试页防检测 / 显示悬浮球：三个开关
  - 开始作答延迟：默认 1.5 秒（检测到题目后等多久再作答）
  - 点「测试接口连通」确认能通，再点右上角「保存」

---

## 五、使用

- **默认模式**：进入考试页，检测到题目后自动抓题、请求模型、回填答案。圆球上会显示状态（思考中 / 已填答）。
- **单击圆球**：展开答案面板，显示题干和模型给的答案（可长按复制）。
- **双击圆球**：立刻重新抓一次题并作答（页面结构特殊、自动没触发时用）。
- **长按圆球**：设置页。

答案回填走的是**页面原生事件**：选项是 `input.click()`，填空是原生 value setter + `input/change` 事件。
提交动作仍然由学习通前端自己完成，不伪造任何网络请求。

---

## 六、防检测做了什么

- 考试页锁死 `document.hidden` / `visibilityState`，拦截 `visibilitychange` / `pagehide` 监听，`document.hasFocus()` 恒为 true。
- 页面被判定为人脸/认证页时**不启用**上述锁死，避免影响人脸核验。
- 答案面板放在 `secureTextEntry` 容器里，系统截屏/录屏抓到的是空白。
- Hook `drawViewHierarchyInRect:afterScreenUpdates:`：App 自己整屏截图前先把悬浮窗隐藏，画完再恢复。
- 监听系统截图通知，截图后 2 秒内悬浮窗保持隐藏。
- 人脸识别相关代码完全没有改动。

---

## 七、排错

日志在手机上的学习通沙盒里：

```
Documents/CXExamAI.log
```

用 Filza 打开：`/var/mobile/Containers/Data/Application/<学习通>/Documents/CXExamAI.log`
（Filza 里搜 `CXExamAI.log` 最快）

如果考试页一直抓不到题，插件会自动把页面 HTML 存成
`Documents/cx-dom-<时间戳>.html`，把这个文件发回来，我按真实结构校准选择器。

常见状态提示：

| 圆球显示 | 含义 |
|---|---|
| `缺Key` | 没填 API Key |
| `待触发` | 关了自动答题，等双击触发 |
| `思考中` | 请求已发出 |
| `网络失败` | Key/地址/网络问题，看日志里的具体报错 |
| `响应异常` | 模型返回不是预期 JSON，看日志原文 |
| `已填答` | 回填完成 |
| `已存DOM` | 抓不到题，已保存页面结构 |

---

## 八、版本

- v1.1.0：去掉 secureTextEntry 面板容器（部分机型渲染异常导致面板全黑），面板改标准视图；设置页显示日志完整路径 + 一键导出日志
- v1.0：考试页抓题 / DeepSeek 作答 / 回填 / 悬浮球 / 防切屏 / 截屏隐藏
