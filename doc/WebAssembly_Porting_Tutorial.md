# 让 C++ 游戏在网页上运行（WebAssembly教程）

本文档旨在为熟悉 C++ 游戏开发但对 WebAssembly (Wasm) 陌生的同学提供一份详细的移植指南。我们将结合 SunnyLand 项目，一步步讲解如何将原本运行在 Windows/Mac 上的游戏“搬”到浏览器中。

## 0. 环境准备：安装 Emscripten

要编译 Wasm，你需要安装 **Emscripten SDK (emsdk)**。假设你已经配置好了 C++ 开发环境（Git, CMake, 编译器等），不同平台的安装步骤如下：

### Mac / Linux
打开终端执行以下命令：

```bash
# 1. 克隆 emsdk 仓库
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk

# 2. 获取并安装最新版
./emsdk install latest

# 3. 激活最新版
./emsdk activate latest

# 4. 配置环境变量 (每次打开新终端都需要运行，或者写入 .bashrc/.zshrc)
source ./emsdk_env.sh
```

### Windows
建议使用 PowerShell 或 CMD：

```powershell
# 1. 克隆 emsdk 仓库
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk

# 2. 获取并安装最新版
./emsdk.bat install latest

# 3. 激活最新版
./emsdk.bat activate latest

# 4. 配置环境变量
./emsdk_env.bat
```

> **验证安装**：
> 在终端输入 `emcc -v`，如果输出了版本信息，说明安装成功！


## 1. WebAssembly 是什么？

### 概念
WebAssembly (简称 Wasm) 是一种运行在现代 Web 浏览器中的**二进制指令格式**。你可以把它想象成一种“通用的汇编语言”，可以在浏览器里以接近原生应用的速度运行。

### 原理
传统的网页主要依靠 JavaScript (JS) 来处理逻辑。虽然 JS 引擎越来越快，但对于计算密集型任务（如游戏渲染、物理模拟），JS 的效率有时仍捉襟见肘，且 C++ 代码无法直接运行。

Wasm 的出现改变了这一点：
1.  **编译目标**：它不是一种你需要手写的语言，而是 C++/Rust/Go 等语言的**编译目标**。
2.  **高性能**：它是二进制格式，体积小，加载快，执行效率接近原生代码。
3.  **安全性**：它运行在浏览器的沙盒环境中，安全可控。

**Emscripten** 是我们使用的核心工具链（Toolchain）。它就像一个“翻译官”，把 C++ 代码（和依赖库如 SDL2/3）编译成 Wasm 二进制文件，并生成配套的 JavaScript“胶水代码”来让浏览器加载和运行这些 Wasm。

---

## 2. 如何将 PC 项目改为网页版？

要把一个桌面游戏移植到 Web，最核心的冲突在于**运行机制**，具体来说是**主循环 (Main Loop)**。

### 为什么需要改代码？

在 PC 上，我们的游戏主循环通常长这样：

```cpp
// 典型的桌面游戏循环
while (is_running) {
    handleInput(); // 处理输入
    update();      // 更新逻辑
    render();      // 渲染画面
    // ... 等待下一帧 ...
}
```

这是一个**无限循环**（死循环），直到游戏退出。在 PC 操作系统上，这没问题。

但在浏览器里，**这是绝对禁止的**。浏览器的主线程不仅要运行你的代码，还要负责渲染网页 UI、响应用户点击等。如果你写了一个 `while(true)` 死循环，JavaScript 引擎就会一直卡在这里，导致**浏览器界面完全卡死**（Freeze），用户无法点击任何东西，甚至无法关闭标签页。

### 解决方案：重构主循环

我们需要把“在这个循环里转圈”改为“**每隔一段时间被浏览器叫醒一次**”。这就像是从“一直盯着锅看水开了没”变成了“定个闹钟，响了就来看一眼”。

**修改前 (src/engine/core/game_app.cpp):**
```cpp
void GameApp::run() {
    // ... 初始化 ...
    while (is_running_) {  // ❌ 浏览器中会导致卡死
        input();
        update();
        render();
    }
    // ... 清理 ...
}
```

**修改后:**
我们需要把循环体提取出来，变成一个单帧函数 `oneIter()`：

```cpp
// 1. 提取单帧逻辑
void GameApp::oneIter() {
    if (!is_running_) return;
    input();
    update();
    render();
}

// 2. 区分平台的运行入口
void GameApp::run() {
    // ... 初始化 ...

#ifdef __EMSCRIPTEN__
    // ✅ Web 模式：告诉浏览器“每一帧请调用一下 oneIter”
    // emscripten_set_main_loop_arg 会利用浏览器的 requestAnimationFrame 机制
    emscripten_set_main_loop_arg([](void* arg) {
        static_cast<GameApp*>(arg)->oneIter();
    }, this, 0, 1);
#else
    // ✅ 桌面模式：保持原有的 while 循环
    while (is_running_) {
        oneIter();
    }
    close();
#endif
}
```

### 构建系统的调整 (CMake)

除了代码，还需要告诉编译器（CMake）我们要生成网页。

**CMakeLists.txt 的关键修改：**

```cmake
if(EMSCRIPTEN)
    # 1. 输出 .html 文件（不仅仅是 .wasm，还需要 html/js 载体）
    set_target_properties(${TARGET} PROPERTIES SUFFIX ".html")

    # 2. 链接选项 (Linker Flags)
    target_link_options(${TARGET} PRIVATE
        "-sUSE_SDL=3"               # 使用 Emscripten 移植好的 SDL3 库
        "-sUSE_ZLIB=1"              # 启用 zlib (解决 FreeType 依赖缺失问题)
        "-sALLOW_MEMORY_GROWTH=1"   # 允许游戏使用的内存超过初始限制
        "--preload-file" "${CMAKE_SOURCE_DIR}/assets@/assets" # ⭐ 关键：文件系统打包
    )
endif()
```

**关于文件预加载 (`--preload-file`)：**
浏览器没有本地文件系统访问权限。`assets@/assets` 这个指令告诉 Emscripten：“把我电脑上的 `assets` 文件夹打包成一个 `.data` 文件。当网页加载时，在浏览器内存里虚拟出一个 `/assets` 目录。” 这样，你的 C++ 代码 `open("assets/config.json")` 才能在浏览器里读到文件。

---

## 3. 定制网页外观：Shell 文件

### 为什么要自定义 Shell？
默认情况下，Emscripten 生成的 HTML 页面包含一个巨大的文本控制台（用于显示 `printf` 内容），看起来像个调试工具，不像游戏。

如果我们想要一个“纯净”的游戏页面（全屏黑色背景，只有游戏画面），就需要提供一个 **Shell 文件**（即 HTML 模板）。

### 实现原理
Shell 文件本质上是一个 HTML 文件，但里面包含一个特殊的占位符 `{{{ SCRIPT }}}`。Emscripten 编译时，会生成加载 Wasm 的 JavaScript 代码，并把这些代码注入到 `{{{ SCRIPT }}}` 的位置。

### shell_minimal.html 解析

我们在 `cmake/shell_minimal.html` 中写了如下内容：

```html
<!doctype html>
<html lang="en-us">
  <head>
    <!-- ... -->
    <style>
      /* 1. CSS 样式：全屏居中，黑色背景 */
      body { 
        background-color: #000; 
        margin: 0; 
        display: flex; 
        justify-content: center; 
        align-items: center; 
        height: 100vh; /* 视口高度 */
      }
      /* 2. Canvas 样式：移除边框 */
      canvas.emscripten { border: 0px none; background-color: #000; }
    </style>
  </head>
  <body>
    <!-- 3. 游戏画布：C++ OpenGL 渲染的目标 -->
    <canvas class="emscripten" id="canvas" oncontextmenu="event.preventDefault()"></canvas>
    
    <script type='text/javascript'>
      // 4. Module 对象：C++ 和 JS 沟通的桥梁
      var Module = {
        canvas: (function() {
          var canvas = document.getElementById('canvas');
          return canvas;
        })()
        // 这里可以定义加载进度条、打印日志等到控制台等逻辑
      };
    </script>
    
    <!-- 5. Emscripten 注入点 -->
    {{{ SCRIPT }}}
  </body>
</html>
```

最后，在 CMake 中应用它：
```cmake
"--shell-file" "${CMAKE_SOURCE_DIR}/cmake/shell_minimal.html"
```

这样，构建出来的 `SunnyLand-Emscripten.html` 就会使用我们的布局，只显示一个干净的游戏窗口。

## 总结

移植过程其实就是解决两个世界的差异：
1.  **执行流差异**：将 `while` 死循环改为 **回调驱动**（Callback-driven）。
2.  **文件系统差异**：使用 **打包预加载**（Preload）将资源塞进虚拟文件系统。
3.  **环境配置**：通过 CMake 和 Emscripten 标志处理库依赖（如 SDL3、Zlib）。
