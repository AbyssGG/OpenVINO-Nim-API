# Getting started

This guide takes a clean checkout to one verified CPU inference. It assumes
the supported baseline: OpenVINO Runtime `2026.4.x`, Nim `2.0.0` or newer, and
Windows x86_64 or Linux x86_64.

## 1. Install the runtime

Install OpenVINO from an official distribution. The Nim package loads the C
runtime at execution time; it does not bundle the runtime, plugins, frontends,
or oneTBB.

On Windows, open a fresh PowerShell and run the official `setupvars.bat` from
the OpenVINO installation. The shell must be able to find `openvino_c.dll` and
the runtime's oneTBB directory.

On Linux, source the official `setupvars.sh`, or export a loader path that
contains `libopenvino_c.so.2640` and its oneTBB dependency. A pip wheel may
provide only the versioned library name; the package tries both the unversioned
and versioned Linux names.

The C library alone is insufficient. `Core` also needs `plugins.xml`, device
plugins and model frontends from the same runtime installation.

## 2. Install the package from a checkout

```shell
git clone https://github.com/AbyssGG/OpenVINO-Nim-API.git
cd OpenVINO-Nim-API
nimble install
```

The Nimble index entry may not exist while `0.1.0` is unreleased. A local
`nimble install` installs the package into Nimble's configured package path.

## 3. Run the examples

The examples use the repository's four-value ReLU fixture, so they do not
require a downloaded model:

```shell
nimble examples
```

To run the command-line example directly:

```shell
nim c -r --path:src examples/sync_infer.nim \
  tests/fixtures/relu_1x4_f32.xml CPU
```

The expected ReLU output is `@[0.0, 2.0, 0.0, 4.0]`.

## 4. Run checks

Runtime-free checks are useful before configuring the OpenVINO environment:

```shell
nimble check
nimble formatCheck
nimble lint
nimble test
nimble docs
```

With OpenVINO headers and the runtime available, run the full local matrix:

```shell
nimble testAbi
nimble testSmoke
nimble testLifecycle
nimble testIntegration
nimble examples
nimble packagingCheck
```

`testAbi` needs `OPENVINO_INCLUDE_DIR` or `INTEL_OPENVINO_DIR`. The runtime
tasks need the C library, plugins and oneTBB on the loader path.

## 5. Use the managed API

The smallest complete program is [examples/minimal.nim](../examples/minimal.nim).
It creates every managed object in the scope that owns it, closes each object
explicitly, and runs one synchronous request. Copy that file before adapting
the code to a real model.

The [API overview](api-overview.md) explains which objects are copied, which
operations block, and where the raw layer begins.

## Common first failures

| Symptom | Likely cause | Next step |
|---|---|---|
| `OpenVinoLibraryError` says the library is missing | Loader path does not contain the C library | Re-run the official setup script in the same shell |
| The C library loads but `newCore()` fails | Plugins, frontends or oneTBB are missing | Use one consistent OpenVINO installation layout |
| A model path works on one host only | Narrow path encoding differs by host | Use the managed path API and read [compatibility](compatibility.md) |
| `nimble install openvino` cannot find a package | `0.1.0` is not indexed yet | Install from the checkout with `nimble install` |

For detailed failure messages, see [Troubleshooting](troubleshooting.md).
