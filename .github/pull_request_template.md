# Pull request

## Summary

<!-- What changed, and why? Keep the managed/raw boundary explicit. -->

## Verification

- [ ] `nimble formatCheck`
- [ ] `nimble lint`
- [ ] `nimble test`
- [ ] Relevant runtime tasks (`testAbi`, `testSmoke`, `testIntegration`, or `examples`)
- [ ] Documentation and `CHANGELOG.md` updated when needed

## Compatibility and risk

<!-- Record OpenVINO/Nim/platform coverage, ownership implications and any
     deliberately unverified combinations. -->

## Checklist

- [ ] No editor metadata, runtime binaries, model weights or credentials were added.
- [ ] No runtime binaries, model weights, credentials or absolute local paths were added.
- [ ] New public symbols have ownership, blocking behaviour and exception docs.
- [ ] `docs/c-api-coverage.md` or the managed API overview is updated.
