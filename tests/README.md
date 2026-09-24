# Tests

The test suite is layered so a failure identifies the boundary that needs
attention. `nimble lint` and `nimble test` are runtime-free; the other tasks
require the pinned OpenVINO headers or runtime as noted below.

| Directory or task | Coverage | Runtime required |
|---|---|---|
| `tests/unit/` / `nimble test` | Shapes, conversions, metadata, library paths and handle lifetime | No |
| `tests/abi/` / `nimble testAbi` | C struct layout, enum values, calling conventions and required symbols | Headers for ABI; runtime for smoke |
| `tests/lifecycle/` / `nimble testLifecycle` | Error paths and native-handle release under ORC and ARC | Yes |
| `tests/integration/` / `nimble testIntegration` | Real CPU ReLU inference in debug and release builds | Yes |
| `tests/packaging/` / `nimble packagingCheck` | Install into a clean Nimble directory and compile outside the checkout | Yes |
| `tests/fixtures/` | Small deterministic model and provenance/checksum record | No |

From the repository root:

```shell
nimble test
nimble testAbi
nimble testSmoke
nimble testLifecycle
nimble testIntegration
nimble packagingCheck
```

The fixture is intentionally tiny and is not a model-quality benchmark. A
test that needs a larger model must document its source, license, checksum and
why it cannot be expressed with the existing fixture.
