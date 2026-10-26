# Harvest Protocol · 田野工程师 Fieldworks

《田野工程师 Fieldworks》项目资料仓库。项目方向为 2D 俯视角像素农业经营，结合设备组装、工程原理学习与农场自动化。

## 项目文档

- [项目总结与设计基准（PDF，18 页）](田野工程师_Fieldworks_项目总结.pdf)

文档整理了已确认的项目方向、视觉基准、玩法循环及初步技术规划。

## 开发流程与进度

先阅读 [开发流程与任务拆解](开发流程与任务拆解.md)，其中记录分步操作、产出、验收条件和实际进度。补充技术基准见 [开发基准](docs/DEVELOPMENT.md)。

第 0 步设计拆解与第 1 步工程建立、启动验证已完成，下一步是地图、角色与基本操作。运行后显示工程基础预览，角色、种植、灌溉和自动化仍待后续步骤实现。实际检查结果见 [验证记录](docs/TEST_REPORT.md)。

## 在 Windows 上启动

引擎固定为 Godot 4.7.2 标准版，使用 GDScript 和 Compatibility 渲染。首次启动会将官方便携版下载到本项目 `.tools/`，核对 SHA-256 后解压，无需修改系统安装。也可以手动准备相同版本。启动脚本启用 Godot 的 self-contained 模式，编辑器配置保存在 `.tools/godot/editor_data/` 内。游戏运行日志与后续存档使用 Godot 的标准 `user://` 目录；Windows 默认为 `%APPDATA%\Godot\app_userdata\田野工程师 · Fieldworks\`。

双击根目录的 `启动游戏.bat`，或从项目目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\start-game.ps1
```

打开 Godot 编辑器：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\start-game.ps1 -Editor
```

检查工程导入与无界面启动：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check-project.ps1
```

Mac 可使用同版本 Godot 直接打开 `project.godot`；目前尚未进行 Mac 实机验证。便携引擎、Godot 缓存和临时验证文件均由 Git 忽略，不上传仓库。
