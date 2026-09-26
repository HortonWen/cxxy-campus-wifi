# 成贤校园网助手（CXXY Campus WiFi Login）

东南大学成贤学院 `Student_CX` 校园网一键连接 / 自动登录工具（Windows）。解决 Windows 电脑连上校园网后不弹认证页、每次都要手动找页面输账号的问题。

![应用图标](exe-app/icon-preview.png)

## 直接使用（推荐）

下载 [成贤校园网助手.exe](成贤校园网助手.exe)，双击运行即可，无需安装任何东西（使用系统自带的 Edge WebView2 内核）。

- 深色无边框现代界面，窗口可拖动、可缩放
- 一键连接 `Student_CX` 并尝试自动认证
- 自动认证失败时兜底打开认证页手动登录
- 检查网络状态、打开自助服务、清除保存
- 密码可选“本机加密保存”（Windows DPAPI 账户级加密，不写明文）

> 未购买代码签名证书，首次运行若 Windows 提示“已保护你的电脑”，点“更多信息 → 仍要运行”即可。

## 备选：PowerShell 脚本版

无需编译，双击 `启动-成贤校园网登录.bat` 打开图形界面。详见 [使用说明.md](使用说明.md)。

## 从源码构建 exe

环境要求：Windows + .NET Framework 4.x（系统自带编译器 csc）+ Microsoft Edge WebView2 运行时（Win10/11 一般已预装）。

```powershell
cd exe-app
powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1
```

构建脚本会自动下载 WebView2 SDK、重新生成图标并用 `csc` 编译出单文件 `exe-app\CXXYNet.exe`（WebView2 组件内嵌为资源，运行时只解出原生加载器到 `%LOCALAPPDATA%\CXXYNet\bin`）。

## 目录结构

```text
├── 成贤校园网助手.exe        已编译的现代界面版（推荐下载）
├── CXXY-CampusNet.ps1        PowerShell 图形界面版主程序
├── 启动-成贤校园网登录.bat   PowerShell 版启动器
├── 创建开机自启.bat/.ps1     开机自动连接登录
└── exe-app/
    ├── build.ps1             一键构建脚本
    ├── make-icon.ps1         图标生成脚本
    ├── src/app.cs            C# 窗口与网络逻辑
    └── src/index.html        现代界面（HTML/CSS/JS）
```

## 说明

- 认证系统为 Dr.COM（城市热点），自助服务 `211.65.40.6:8080/Self`，认证页由访问 `6.6.6.6` 或学校主页触发。
- 自动登录优先按认证页真实表单提交，失败后尝试 Dr.COM ePortal 常见接口，再失败则打开认证页手动登录。
- 自动登录接口按学校公开资料编写，建议在校园网内实测；如页面结构变化，欢迎提 Issue 一起适配。
