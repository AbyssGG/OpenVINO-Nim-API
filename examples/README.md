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
| `dynamic_shape.nim` | Partial shapes, reshape, and one compiled model inferring batches 1, 3 and 7 | None |

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

Use [Getting started](../docs/getting-started.md) for loader setup and
[the API overview](../docs/api-overview.md) for the ownership rules that the
examples intentionally make visible.
