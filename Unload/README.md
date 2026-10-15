# Unload

A small macOS menu bar app that shows what's holding your memory and frees it in one click,
built for people running local LLMs and generative AI.

Same design and build setup as [Displate](../README.md). Swift / SwiftUI, no dependencies, macOS 14+.

## Features

| | |
|---|---|
| **Menu bar** | Memory icon with live % used (or GB used, or icon only). Turns orange/red under memory pressure. |
| **Memory overview** | Used / total with a gauge, pressure level, 2-minute history, and the breakdown Activity Monitor uses: app, wired, compressed, cached. Plus swap and GPU memory (unified memory on Apple silicon). |
| **Top processes** | The 5 apps using the most memory; **Show all** lists every process with search by name or PID. Helper processes are grouped under their app; click an app to see them. Python / Node processes show the script they run (`python3.11 · mlx_lm.server`) so you can tell them apart. |
| **One-click quit** | ✕ quits gracefully. If it's still running a few seconds later, the button turns into **Force Quit**. ⌥-click the ✕ to force quit right away. System processes offer **Admin…** (asks for your password). Critical processes (WindowServer, launchd…) are protected. |
| **AI memory** | Detects Ollama, LM Studio, MLX, llama.cpp, ComfyUI, koboldcpp, Draw Things, and Python processes using torch/transformers/diffusers. Shows models loaded in **Ollama** and **LM Studio**, each with an **Unload** button, which frees the memory without quitting the server. **Free all** unloads every model and quits every AI process. |
| **Purge disk cache** | ✨ button runs `purge` (asks for your password). This only releases cached files, not app memory. |
| **Freed indicator** | Pill below the menu bar: "Freed 7.8 GB". |

## Permissions

Nothing special. Reading and quitting your own processes needs no permission. Processes owned by
macOS or other users ask for your administrator password when you quit them.

## Why memory stays used after "closing everything"

The usual culprits with local AI:

- **Ollama** keeps the last model loaded for 5 minutes (or longer with `OLLAMA_KEEP_ALIVE`) in
  `ollama_llama_server`. Use **Unload** on the model.
- **LM Studio** keeps models loaded until you eject them, even with its window closed.
- A **Python** script (MLX, PyTorch, a Gradio UI) still running in a terminal tab or as a background job.

## Building

```bash
./scripts/build-app.sh              # native architecture
./scripts/build-app.sh --universal  # arm64 + x86_64 (needs Xcode)
cp -R build/Unload.app /Applications/ && open /Applications/Unload.app
```

Every push also builds it on GitHub Actions (the `Unload` artifact of the **Build** workflow).
It is ad-hoc signed, so the first launch needs right-click → **Open**.
