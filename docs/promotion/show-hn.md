# Show HN: OpenVINO Runtime bindings for Nim

Submission URL: https://github.com/AbyssGG/OpenVINO-Nim-API

## Suggested first comment

I made OpenVINO Nim API, a community binding to the OpenVINO Runtime C API.
v0.1.0 provides both idiomatic Nim handles with explicit lifetime management
and a separate header-faithful raw layer. It is Apache-2.0 and not an official
Intel/OpenVINO project.

The idea is to run inference in native Nim applications without a Python
runtime. It still requires the OpenVINO runtime, plugins and model files;
this is not a standalone single-file distribution.

Implemented: synchronous inference, model metadata, tensors, device discovery,
properties, profiling and explicit compiled-model blob I/O. The supported
baseline is Nim >= 2.0.0 and OpenVINO 2026.4.x, with CPU verification on
Windows/Linux x86_64 against 2026.4.0. No GPU/NPU/macOS inference or performance
claims yet. Async callbacks and preprocessing are future work.

The README includes installation and a managed inference example using a
bundled weight-free ReLU fixture. I'd appreciate feedback on API ergonomics
and where this could be useful in small native deployments.
