# PDF 图片反转工具

将 PDF 或图片上传后，自动转为灰度并反转颜色，支持批量处理、预览对比、导出 PDF。

## 功能

- 上传 PDF / PNG / JPG（点击或拖拽）
- 逐页转为灰度并反转颜色
- 悬停预览原图对比
- 复选框选择，支持全选 / 取消全选
- 批量保存到文件夹（原生 macOS 对话框）
- 单张图片下载
- 一键生成反转后的 PDF
- 深色主题 UI

## 启动方式

### 方式一：原生桌面应用（推荐）

```bash
npm run build:native    # 首次构建，生成 .app
npm run start:native    # 启动应用
```

构建后在 `build/PDF 图片反转工具.app` 可直接双击打开。

### 方式二：浏览器

```bash
npm start
```
自动打开 Safari 访问 `http://localhost:3456`。

## 技术栈

- **前端**：HTML + CSS + JavaScript（深色主题、毛玻璃效果）
- **PDF 处理**：pdfjs-dist + jsPDF
- **桌面壳**：原生 Swift + WKWebView（仅 178KB）
- **文件对话框**：macOS 原生 NSOpenPanel / NSSavePanel
