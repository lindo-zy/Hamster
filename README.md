# 「仓」输入法

一款基于「[中州韻輸入法引擎／Rime Input Method Engine](https://github.com/rime/librime)」的 iOS 版本输入法.

# License

本项目最初采用 GPL-3.0 许可。从 v2.1.0 开始，它变更为 MIT 许可。

后续代码是否会在开源？

目前「仓」已经在做商业化的相关功能了，在没有资金的情况下，不打算在开源了。

感谢大家的支持。

# 如何编译运行

在 1.0 版本，很多伙伴 `clone` 项目后都无法直接运行，多数问题是被被卡在 `librime` 的编译下了，于是新版本将这步省略了。

原 LibrimeKit 预编译发布地址已失效。本仓库的 `librimeFramework.sh` 会从固定版本源码编译 Rime 1.9.0、声笔引擎和 Lua 插件，生成 iOS arm64 的 XCFramework；无需 CocoaPods。已存在的完整 Framework 可以复用，也可以通过 `LIBRIME_FRAMEWORKS_URL` 指定原始 `Frameworks.tgz` 的镜像地址，通过 `LIBRIME_FRAMEWORKS_SHA256` 指定其 SHA256。源码路径只生成真机 arm64 切片，不包含模拟器切片。

> 感谢 @amorphobia 为 LibrimeKit 提交的 Github Action 配置

1. 下载编译后的 Framework

```sh
make framework
```

2. 下载内置方案

```sh
make schema
```

3. XCode 打开项目并运行（我个人使用的开发环境 Intel X86，MacOS 14，XCode 15）

```sh
xed .
```

## 构建 TrollStore（巨魔）安装包

需要 macOS、完整 Xcode（CI 固定 Xcode 16.4）和 CMake（`brew install cmake`）。在 Apple Silicon 上，内置方案使用的旧 macOS OpenCC 工具需要 Rosetta，或者通过 `OPENCC_BINARY` 指定本机可运行的 OpenCC。GitHub workflow 使用 Intel runner。

```sh
./build-tipa.sh
```

脚本会准备依赖及内置方案，以 Release 构建主 App 和两个键盘扩展，将最低系统版本设为 **iOS 16.0**，关闭 Xcode 证书签名，随后用本地 ad-hoc 签名写入各自的权限，生成 `Payload/Hamster.app` 格式的 `.tipa`。**不需要 Apple ID、开发者证书、描述文件或签名 Secrets，也无需定期续签。** CoreTrust 签名由设备上的 TrollStore 在安装时处理。

输出位置：`artifacts/trollstore/Hamster-3.0.0-1-ios16-arm64.tipa`，同时生成 `.tipa.sha256` 校验文件。版本号从构建结果读取。

可选用法：

```sh
./build-tipa.sh --prepare-only
./build-tipa.sh --skip-dependencies --output-dir ./artifacts/custom
./build-tipa.sh --app /path/to/Hamster.app
```

`--app` 只处理已经以 iOS 16.0 构建的真机 App；脚本会拒绝缺失键盘扩展、共享权限、方案资源或架构不正确的包。打包不会修改原始 App。Rime 的源码版本固定，并应用原 LibrimeKit 的输入替换 API 补丁；链接检查覆盖两个引擎、`RimeReplaceInput` 和静态 Lua 模块。内置雾凇也固定到适合此旧引擎的版本，避免引入要求更新引擎的方案配置。

### GitHub Actions

将本次改动推送到你的 GitHub 仓库后：

1. 打开 **Actions → Build TrollStore TIPA → Run workflow**，选择分支并运行。
2. 等待构建成功，在该次运行的 **Artifacts** 下载 `Hamster-ios16-arm64-tipa`。
3. 解压下载的 artifact ZIP，取出里面的 `.tipa`，在 iPhone/iPad 上用 TrollStore 打开并安装。

workflow 也会在 `main` 的 push、指向 `main` 的 PR 和 `v*` tag push 时运行。首次运行会从源码编译依赖，耗时较长；后续使用与源码、构建脚本和 Xcode 版本绑定的缓存。workflow 只上传 Actions artifact，不自动发布 Release。

### 安装与系统范围

安装后先启动 Hamster，完成内置方案部署，再到 **设置 → 通用 → 键盘 → 键盘 → 添加新键盘** 添加对应键盘，并开启“允许完全访问”，以便主 App 和键盘扩展共享配置、词库及文件。

根据 [TrollStore 官方说明](https://github.com/opa334/TrollStore#readme)，本包的 iOS 16+ 巨魔安装范围是 **16.0–16.6.1、16.7 RC（20H18）和 17.0**。普通 16.7.x、17.0.1 及更高系统不能因 `.tipa` 后缀或降低部署版本而获得 TrollStore 支持；设备必须已经安装可用的 TrollStore。

Bundle ID 与原版相同，不能与同 ID 的 App Store 版本并存；更换安装渠道前请自行备份配置和词库。原有 iCloud/CloudKit 权限保留，但此构建没有原开发者的 Apple 服务身份，不保证 iCloud、在线方案库或推送可用。核心使用方式是本地方案、词库和键盘；证书与 Apple 服务授权是不同问题。

构建及签名验证不能代替真机测试。安装、首次部署、两个键盘的启用及共享数据访问仍需在目标设备验证。

# 第三方库

仓输入法的功能的开发离不开这些开源项目：

* [librime](https://github.com/rime/librime) (BSD License)
* [KeyboardKit](https://github.com/KeyboardKit/KeyboardKit.git) (MIT License)
* [Squirrel](https://github.com/rime/squirrel) (GPL-3.0 license)
* [Runestone](https://github.com/simonbs/Runestone.git) (MIT License)
* [TreeSitterLanguages](https://github.com/simonbs/TreeSitterLanguages.git) (MIT License)
* [ProgressHUD](https://github.com/relatedcode/ProgressHUD) (MIT License)
* [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (MIT License)
* [Yams](https://github.com/jpsim/Yams) (MIT License)
* [GCDWebServer](https://github.com/swisspol/GCDWebServer)

# 致谢

感谢 TF 版本交流群中的 @一梦浮生，@CZ36P9z9 等等伙伴对测试版本的反馈与帮助，也感谢 @王牌饼干 为输入法制作的工具。

# 捐赠

如果「仓」对您有帮助，可以请我吃份「煎饼馃子」，感激不尽~

> 注意：不接收有偿咨询服务，请勿因此打赏，谢谢。

<img src="https://ihsiao.com/aliPay.jpeg" width="207" height="281" />
<img src="https://ihsiao.com/wechatPay.jpeg"  width="207" height="281" />


### AppStore

<a href="https://apps.apple.com/cn/app/%E4%BB%93%E8%BE%93%E5%85%A5%E6%B3%95/id6446617683?itscg=30200&amp;itsct=apps_box_appicon" style="width: 170px; height: 170px; border-radius: 22%; overflow: hidden; display: inline-block; vertical-align: middle;"><img src="https://is4-ssl.mzstatic.com/image/thumb/Purple126/v4/16/b3/b8/16b3b836-12aa-206a-f849-79e37bf6528c/AppIcon-0-1x_U007emarketing-0-10-0-85-220.png/540x540bb.jpg" alt="仓输入法" style="width: 170px; height: 170px; border-radius: 22%; overflow: hidden; display: inline-block; vertical-align: middle;"></a>

<a href="https://apps.apple.com/cn/app/%E4%BB%93%E8%BE%93%E5%85%A5%E6%B3%95/id6446617683?itsct=apps_box_badge&amp;itscg=30200" style="display: inline-block; overflow: hidden; border-radius: 13px; width: 250px; height: 83px;"><img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83&amp;releaseDate=1680912000" alt="Download on the App Store" style="border-radius: 13px; width: 250px; height: 83px;"></a>
