# 阶段验证记录

## 2026-10-27 · 第 1 步：工程基础

### 环境与来源

- Windows x86_64，Godot 4.7.2 标准版。
- 引擎版本输出：`4.7.2.stable.official.ed1daf0bf`。
- 官方下载：<https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable>。
- 官方压缩包 SHA-256：`731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953`，本地核对一致。
- Compatibility / OpenGL 渲染。

### 执行与结果

| 检查 | 实际执行 | 结果 |
| --- | --- | --- |
| 工程导入 | `tools/check-project.ps1` 调用 `--headless --editor --import` | 通过，无脚本解析错误 |
| 无界面启动 | 同一脚本调用 `--headless -- --smoke-test` | 通过，输出 `FIELDWORKS_BOOT_OK`，退出码 0 |
| 图形启动 | 引擎运行主场景，1440×900，保存视口截图 | 通过，输出 `FIELDWORKS_CAPTURE_OK`，退出码 0 |
| 显示检查 | 人工查看保存的窗口截图 | 中文、按钮、网格、布局正常，无裁切 |
| Git 忽略规则 | 检查 `.tools/`、`.godot/`、`tmp/` | 引擎、导入缓存与临时检查文件均被忽略 |
| 文本差异 | `git diff --check` | 通过 |

复现检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check-project.ps1
```

图形验证的本机临时截图为 `tmp/qa/step-01-window.png`；日志为 `tmp/qa/import.log` 与 `tmp/qa/boot.log`，这些临时文件不提交 Git。

### 处理过的环境问题

受限运行环境起初阻止 Godot 写入默认用户目录。启动脚本已启用官方 self-contained 编辑器模式，使编辑器配置位于 `.tools/godot/editor_data/`。游戏的标准 `user://` 日志目录仍需要当前用户具有正常写权限；本次在获得运行权限后完成检查。没有关闭安全检查或修改系统安全设置。

### 本次结论与限制

第 1 步运行基础已通过，可以进入第 2 步。当前窗口是工程预览，网格不包含可操作角色或农业模型。没有将玩法、交易、存档或灌溉记为完成；这些系统尚未开始。Mac 尚未实机测试。

## 2026-10-27 · 第 2 步：农场、角色与地块检查

本节记录第 2 步完成后的状态；上节为第 1 步的历史验收记录。

### 执行与结果

| 检查 | 实际执行与覆盖 | 结果 |
| --- | --- | --- |
| 导入与启动 | `tools/check-project.ps1` | 通过，无解析或运行错误 |
| 无界面行为回归 | `tests/test_world.gd`，地图、边界、碰撞、斜向速度、松键停止、沿墙滑动、长帧防穿墙 | 55 项检查通过 |
| 视口输入路由 | 从主场景的 Viewport 投递点击事件，在 1600×1000、1280×800、1152×720 下点击试验田、农舍、池塘及边界地块 | 选中结果和检查面板均正确；包含在行为检查中 |
| 实际图形窗口输入 | 在运行场景中注入 D、方向键、A、G、R 的物理按键事件，等待正常帧推进 | 63 项检查通过，其中新增 8 项实际窗口检查；输出 `FIELDWORKS_NATIVE_INPUT_OK` |
| 窗口显示 | 实际运行 1440×900 和 1152×720 窗口，保存并查看截图 | 中文、地图、角色、检查面板和按钮正常，无裁切 |
| 临时资源隔离 | 检查脚本在 `tmp/` 写入 `.gdignore` | QA 截图不再被 Godot 当作游戏资产导入 |

图形检查复用同一组地图用例，并增加 8 项运行窗口的输入验证，共 63 项。

无界面检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check-project.ps1
```

实际图形窗口输入检查：

```powershell
& .\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1440x900 --script res://tests/test_world.gd
```

本机临时截图：`tmp/qa/step-02-window.png`、`tmp/qa/step-02-small-window.png`，均不提交 Git。

### 本次结论与限制

第 2 步验收通过，可进入第 3 步。当前已能探索农场、碰撞和检查地块；尚无耕作工具、作物模拟、交易、存档或灌溉。像素场景为程序绘制的原型资产，成品美术统一仍在第 13 步。Mac 尚未实机测试。

## 2026-10-27 · 第 3 步：地块、工具和资源反馈

本节为第 3 步完成后的状态，之前章节保留各阶段的历史结果。

| 检查 | 实际覆盖 | 结果 |
| --- | --- | --- |
| 导入与启动 | 更新后的 `tools/check-project.ps1` | 通过 |
| 工具与资源行为 | 翻土、三种种子、浇水、湿度上限、空水壶、池塘补水、未成熟保护及成熟状态下的收获接口 | 工具检查 82 项通过 |
| 失败操作不改状态 | 未翻土、重复翻土、重复播种、作物占地、种子耗尽、不可耕地、地图外、距离过远、障碍遮挡和水壶状态 | 每种拒绝操作比较全部地块与资源快照，通过 |
| 工具栏到地图的输入 | 通过视口发送工具快捷键、种子按钮、工具按钮和地图点击，检查种子扣除、土壤变化与检查面板 | 通过，包含在 82 项检查中 |
| 原有地图回归 | 55 项无界面地图检查、63 项图形地图与键盘检查 | 均通过 |
| 图形操作与截图 | 在实际图形窗口中复跑工具检查，合法完成三种种子的翻土、播种、浇水，再保存正常与最小窗口截图 | 84 项通过，其中 2 项为截图保存检查 |
| 显示检查 | 查看 1440×900 与 1152×720 的操作后截图 | 中文、工具栏、选择状态、种子计数、水壶和地块信息完整，无裁切 |

工具检查命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check-project.ps1
```

图形操作及截图复现：

```powershell
& .\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1440x900 --script res://tests/test_tools.gd -- --capture-dir=C:/Users/64969/Desktop/Harvest-Protocol/tmp/qa
```

临时截图为 `tmp/qa/step-03-1440x900.png` 和 `tmp/qa/step-03-1152x720.png`，不提交 Git。截图展示的是通过合法工具操作形成的地块状态，成熟收获只用单独测试夹具验证接口。

### 本次结论与限制

第 3 步验收通过。当前支持手工翻土、选择种子、播种、人工浇水与补水；作物暂不推进生长，天气和自然水分变化、交易、持久存档与灌溉装置尚未实现。工具栏中的收获接口会拒绝未成熟作物。关闭游戏后当前操作尚不能恢复，存读档仍在第 7 步实现。
