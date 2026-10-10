# Getting started

This guide takes a clean checkout to one verified CPU inference. It assumes
the supported baseline: OpenVINO Runtime `2026.4.x`, Nim `2.0.0` or newer, and
Windows x86_64 or Linux x86_64.

## 1. Install the runtime

Install OpenVINO from an official distribution. The Nim package loads the C
runtime at execution time; it does not bundle the runtime, plugins, frontends,
or oneTBB.

On Windows, open Command Prompt (CMD) and run the official `setupvars.bat`.
Replace the path below with your OpenVINO installation directory:

```bat
call "C:\path\to\openvino\setupvars.bat"
```

Run the remaining installation and inference commands in the same CMD
session. Running a batch file from PowerShell sets the environment in a child
process; those changes do not propagate back to the parent PowerShell session.
The loader must be able to find both `openvino_c.dll` and oneTBB.

On Linux, source the official setup script in the current Bash session:

```shell
source /path/to/openvino/setupvars.sh
```

For a pip installation, add the library directory to the loader path. Use the
Python environment where OpenVINO is installed:

```shell
OV_LIB_DIR=$(python -c 'import openvino, os; print(os.path.join(os.path.dirname(openvino.__file__), "libs"))')
export LD_LIBRARY_PATH="$OV_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```

The package tries both `libopenvino_c.so` and `libopenvino_c.so.2640`. Some
wheel layouts provide only the versioned name. Keep oneTBB available on the
loader path as well.

The C library alone is insufficient. `Core` also needs `plugins.xml`, device
plugins and model frontends from the same runtime installation.

## 2. Install the package from a checkout

```shell
git clone https://github.com/AbyssGG/OpenVINO-Nim-API.git
cd OpenVINO-Nim-API
nimble install
```

Version `0.1.0` is released, but its Nimble index entry is not published yet.
Run `nimble install` from the checkout to install the package into Nimble's
configured package path. The package and import name are both `openvino`.

## 3. Run the examples

The examples use the repository's four-value ReLU fixture, so they do not
require a downloaded model:

```shell
nimble examples
```

Run commands from the repository root so that the fixture path resolves.
To run the command-line example directly in CMD or Bash:

```shell
nim c -r --path:src examples/sync_infer.nim tests/fixtures/relu_1x4_f32.xml CPU
```

The expected ReLU output is `@[0.0, 2.0, 0.0, 4.0]`.

This fixture has no weights, so it does not require a separate `.bin` file.
The example supplies four `float32` values and verifies `max(0, x)`; changing
only the model path does not adapt it to an arbitrary model.

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

For your model, check the input count, each port's `elementType()` and static
`shape()`. Prepare data for every required input and replace the ReLU output
check with the expected behavior of your model. Keep an IR model's `.xml` and
`.bin` files together when it has weights. Image layout, normalization and
postprocessing are application responsibilities.

The [API overview](api-overview.md) explains which objects are copied, which
operations block, and where the raw layer begins.

## Common first failures

| Symptom | Likely cause | Next step |
|---|---|---|
| `OpenVinoLibraryError` says the library is missing | Loader path does not contain the C library | Re-run the official setup script in the same shell |
| The C library loads but `newCore()` fails | Plugins, frontends or oneTBB are missing | Use one consistent OpenVINO installation layout |
| A model file cannot be found | A relative path resolves from a different working directory | Run from the repository root or use an absolute model path |
| `nimble install openvino` cannot find a package | `0.1.0` is not indexed yet | Install from the checkout with `nimble install` |

For detailed failure messages, see [Troubleshooting](troubleshooting.md).
