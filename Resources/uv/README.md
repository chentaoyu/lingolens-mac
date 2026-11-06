# 内置 uv

把 macOS (arm64) 的 `uv` 可执行文件放在此目录，文件名为 `uv`。

构建 App 时该文件会被复制到 `LingoLens.app/Contents/Resources/uv/uv`。
首次启动时，`PythonEnvironment` 会使用它创建 Python 3.12 虚拟环境并安装固定版本的 mlx-vlm。

开发期如果此目录为空，运行时会依次回退到：

1. 环境变量 `LINGOLENS_UV`
2. `/opt/homebrew/bin/uv`
3. `/usr/local/bin/uv`
4. `~/.local/bin/uv`
5. `~/.cargo/bin/uv`
6. `PATH` 中的 `uv`

安装示例：`brew install uv`。
