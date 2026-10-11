# Examples

Every example is compiled and run by `nimble examples` against the small ReLU
fixture in `tests/fixtures/`. They use the public managed API; they do not
download models or depend on a YOLO/GenAI application.

| File | Demonstrates | Command-line arguments |
|---|---|---|
| `list_devices.nim` | Runtime version and device discovery | None |
| `minimal.nim` | The smallest complete synchronous inference | None |
| `sync_infer.nim` | Model metadata and verified inference with four `float32` inputs | `<model.xml> <device>` |
| `tensor_basics.nim` | Shapes, element types and safe/unsafe data paths | None |
| `profiling.nim` | Per-node profiling and property configuration | None |

Run the complete set after configuring OpenVINO:

```shell
nimble examples
```

Run one file directly from the repository root:

```shell
nim c -r --path:src examples/sync_infer.nim tests/fixtures/relu_1x4_f32.xml CPU
```

`sync_infer.nim` accepts a model path and device, but its input values and
`max(0, x)` output check are specific to the ReLU fixture. To use another
model, update the input count, element types, shapes, data preparation and
output validation. The fixture has no weights; an IR model with weights also
needs its `.bin` file.

## Obtaining another model

The bundled fixture is the best first test: no download or conversion is
needed. For your own ONNX model, use OpenVINO's offline conversion tools in a
separate Python environment with `openvino==2026.4.0` installed:

```shell
ovc /path/to/model.onnx --output_model /path/to/converted/model.xml
```

See [OpenVINO model conversion](https://docs.openvino.ai/2026/openvino-workflow/model-preparation.html)
for supported source formats and conversion options. Keep the generated XML
and BIN together. Python is needed for this preparation step, not for the Nim
inference application.

To find a public example model, browse
[Open Model Zoo](https://github.com/openvinotoolkit/open_model_zoo) and follow
the chosen model's download/conversion instructions. Check its license,
input layout, normalization, output meaning and compatibility with your
OpenVINO version before use; no Zoo model is tested by this repository.

For image classification, prepare the required image tensor in application
code and interpret the output scores using that model's labels. The bindings
do not include image decoding, resizing, normalization, a classification
pipeline or model downloading. Do not run the ReLU example unchanged against
a classification model.

Use [Getting started](../docs/getting-started.md) for loader setup and
[the API overview](../docs/api-overview.md) for the ownership rules that the
examples intentionally make visible.
