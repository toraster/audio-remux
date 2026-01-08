# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mac application for losslessly replacing audio in MP4 files. Target users are "cover song" video creators who need to swap original audio with new recordings while preserving video quality.

## Tech Stack

- **UI**: SwiftUI + AppKit (macOS 11.0+)
- **Media Processing**: FFmpeg (bundled binary)
- **Audio Sync**: Accelerate Framework (vDSP for cross-correlation)
- **Waveform Display**: AVFoundation + Core Graphics

## Architecture

Three-layer architecture:
- **View Layer**: SwiftUI views (FileDropZone, WaveformView, ExportSettingsView)
- **ViewModel Layer**: ProjectViewModel, SyncAnalyzerViewModel
- **Service Layer**: FFmpegService, FFprobeService, AudioAnalyzer, WaveformGenerator

## Key FFmpeg Commands

```bash
# Basic audio replacement
ffmpeg -i video.mp4 -i audio.wav -map 0:v -map 1:a -c:v copy -c:a flac output.mp4

# With positive offset (delay audio)
ffmpeg -i video.mp4 -itsoffset 0.5 -i audio.wav -map 0:v -map 1:a -c:v copy -c:a flac output.mp4

# With negative offset (trim audio start)
ffmpeg -i video.mp4 -ss 0.3 -i audio.wav -map 0:v -map 1:a -c:v copy -c:a flac output.mp4

# Extract audio for analysis
ffmpeg -i video.mp4 -vn -c:a pcm_s16le original_audio.wav

# Probe file info
ffprobe -v quiet -print_format json -show_streams video.mp4
```

## Audio Codec Options

- **FLAC** (recommended): Lossless compression
- **ALAC**: Apple Lossless
- **PCM (16/24-bit)**: Uncompressed

## Git Workflow

**Claudeの挙動の設定を除き、mainブランチでは直接作業しない。** 必ず作業用ブランチを作成してから実装を行うこと。

```bash
# ブランチ命名例
git checkout -b feature/add-new-feature
git checkout -b fix/bug-description
git checkout -b refactor/module-name
```
## Development Notes

- FFmpeg binaries should be bundled in `Resources/` directory
- App requires sandbox entitlements for file access (`files.user-selected.read-write`)
- For long videos (10+ min), limit cross-correlation analysis to 30-second windows
- Handle sample rate mismatch with automatic resampling
