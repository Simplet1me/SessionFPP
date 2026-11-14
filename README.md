# SessionFPP

Session Skate Sim 原生 C++ 第一人称视角 mod，使用 UE4SS 3.0.1。

关闭游戏，解压完整发行包，双击 Install.cmd。脚本自动查找 Steam 游戏目录，也可以指定：

```powershell
.\install.ps1 -GamePath 'F:\SteamLibrary\steamapps\common\Session'
.\uninstall.ps1 -GamePath 'F:\SteamLibrary\steamapps\common\Session'
```

进入游戏后按 Y 切换第一/第三人称。默认第三人称，按住不连续切换。失焦和摔倒期间暂时恢复第三人称。相机编辑器使用独立视角目标时不覆盖它。

卸载：关闭游戏后双击 Uninstall.cmd。脚本只移除本包记录的文件；已有 UE4SS 和其他 mod 保留。本包安装的 UE4SS 只有在文件未修改、没有其他 mod 使用时才会移除。日志和自定义配置保留。

可选：在游戏 SessionGame/Binaries/Win64 下新建 SessionFPP.ini：

```ini
[Camera]
FOV=110
EyeForwardCm=18
EyeUpCm=0
PitchDegrees=-10
```

EyeForwardCm 调整眼睛前方距离，EyeUpCm 调整高度，PitchDegrees 负数向下看。视角采用角色 GetActorEyesViewPoint 眼点与游戏相机水平朝向；不隐藏全身，可能需要按角色帽子/发型调整眼点以避免穿模。

日志：SessionGame/Binaries/Win64/SessionFPP.log。游戏更新导致特征码失配时自动禁用，不使用旧地址强行加载。与其他修改相机的 mod 同时启用可能互相覆盖，应关闭它们的第一人称功能。

构建：Visual Studio 2022 或更新版本的 x64 C++ 工具、CMake 3.21+；运行 packaging/build-native.cmd，再运行 powershell -File packaging/build-release.ps1。发行包包含源码和许可证。

本项目参考 SessionOpenMP 的 ASkaterCameraActor::Tick、USceneComponent::SetWorldLocationAndRotation 特征码、相机组件偏移和恢复流程；安装脚本改编自 SessionHistoryChallengeDisplay。遵循 GPL-3.0-or-later，含原运行时链接许可；MinHook、UE4SS 许可证随包提供。

验证范围：构建与隔离目录安装/卸载验证不等同于游戏实测。不同角色、地图、回放和游戏版本需在游戏内确认。
