# 手机功能模块接入

AI Passport 用一个稳定的模块 `id` 连接桥接程序、电脑设置页和 Android 显示页。模块清单的唯一来源是 [`mac/modules.js`](../mac/modules.js) 中的 `moduleCatalog`，桥接程序通过 `/status` 和 WebSocket `snapshot` 将它下发给各端。

## 模块结构

```js
{
  id: 'weather',
  name: '桌面天气',
  shortName: '天气',
  category: '信息',
  summary: '显示当前位置的天气和未来几小时变化。',
  icon: 'cloud.sun.fill',       // macOS SF Symbol
  phoneIcon: '☀',              // Android 功能卡片字符
  settings: 'weather',         // 电脑端设置适配器名称
  features: ['当前天气', '逐时预报']
}
```

`id` 写入用户的 `modules.json`，发布后不要更改。清单只描述模块，不存用户数据。模块配置继续放在 `modules.json` 中，并由 `normalizeModules()` 验证长度、类型和允许的字段。

## 接入顺序

1. **注册清单**：在 `moduleCatalog` 添加描述；`ids` 会自动接受新的模块 ID。
2. **定义配置**：扩展 `defaultModules` 和 `normalizeModules()`，对所有来自界面的字段做白名单验证。
3. **Mac 设置页**：在 `moduleSettingsPage(_:)` 中按 `settings` 选择设置视图，保存时调用 `saveModules()`。
4. **Windows 设置页**：在 `openModule()` 中挂载对应面板，保存时调用 `window.passport.saveModules()`。
5. **Android 显示页**：创建模块页面，在 `showModule()` 中注册模块 ID，并从 `snapshot.modules` 读取配置。功能抽屉的名称、说明和图标会自动读取统一清单。
6. **验证**：给 `mac/modules.test.js` 增加配置边界测试，运行 `npm test`，再编译 Android、macOS 和 Windows。

## 数据流

```text
电脑设置页
    │ POST /modules
    ▼
bridge.js ──校验并保存── modules.json
    │
    ├── /status ───────────────► Mac / Windows 管理端
    └── WebSocket snapshot ────► Android 功能抽屉与模块页
```

桥接程序只接受 `normalizeModules()` 返回的数据。Android 不直接修改模块配置，避免多端同时编辑产生覆盖。

## 完成检查

- 模块关闭后不出现在手机功能抽屉。
- 模块设置重新启动电脑端后仍然保留。
- 手机断线重连后收到清单和配置。
- 未知模块 ID、重复 ID 和超长字段会被拒绝。
- 横屏与竖屏都能打开、收起并回到上次模块。
