# SPDX-License-Identifier: Apache-2.0

## Lifetimes around asynchronous inference: closing or dropping a request
## while it runs, and closing a completion queue and its requests in either
## order.
##
## `nimble testLifecycle` runs this under ORC and ARC; `nimble memcheck` covers
## the same release paths under valgrind through `examples/async_infer.nim`.
## A failure here is a crash or a hang rather than a wrong value, so each test
## is written to finish quickly when the release order is right.

import std/[os, unittest]

import openvino

const
  fixturePath = currentSourcePath().parentDir.parentDir / "fixtures" /
    "relu_1x4_f32.xml"
  busyLength = 32_000_000
  noWait = initDuration(milliseconds = 0)
  patience = initDuration(seconds = 30)

proc compileBusy(core: Core): CompiledModel =
  let model = core.readModel(fixturePath)
  defer: model.close()
  model.reshape(initPartialShape(initShape(1, busyLength)))
  core.compileModel(model, "CPU")

proc startAndAbandon(compiled: CompiledModel; queue: CompletionQueue) =
  ## Starts a request and drops the last reference without closing it, so
  ## the destructor has to cancel, wait and release it.
  let request = compiled.createInferRequest()
  queue.attach(request, 99)
  request.startAsync()

suite "closing a running request":
  test "close cancels, waits and releases a running request":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileBusy()
    defer: compiled.close()
    for round in 1 .. 3:
      let request = compiled.createInferRequest()
      request.startAsync()
      request.close()
      check request.isClosed
      expect OpenVinoArgumentError:
        request.wait()

  test "the destructor releases a running, attached request":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileBusy()
    defer: compiled.close()
    let queue = newCompletionQueue(capacity = 3)
    defer: queue.close()
    for round in 1 .. 3:
      startAndAbandon(compiled, queue)
    # Each abandoned request was detached when it was released, so nothing
    # remains attached or pending and the capacity is free again.
    check queue.pending == 0
    let again = compiled.createInferRequest()
    defer: again.close()
    queue.attach(again, 1)

  test "closing an attached request removes its pending completion":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(fixturePath, "CPU")
    defer: compiled.close()
    let queue = newCompletionQueue(capacity = 1)
    defer: queue.close()
    let request = compiled.createInferRequest()
    queue.attach(request, 5)
    request.startAsync()
    request.wait()
    check queue.pending == 1
    request.close()
    check queue.pending == 0
    check queue.next(noWait).isNone

suite "queue and request lifetimes":
  test "the queue closed first: requests keep working and close cleanly":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(fixturePath, "CPU")
    defer: compiled.close()
    let queue = newCompletionQueue(capacity = 2)
    let first = compiled.createInferRequest()
    let second = compiled.createInferRequest()
    queue.attach(first, 0)
    queue.attach(second, 1)
    queue.close()
    for request in [first, second]:
      request.startAsync()
      request.wait()
    first.close()
    second.close()

  test "requests closed first: the queue is still usable, then closes":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(fixturePath, "CPU")
    defer: compiled.close()
    let queue = newCompletionQueue(capacity = 1)
    block:
      let request = compiled.createInferRequest()
      queue.attach(request, 0)
      request.startAsync()
      discard queue.next(patience)
      request.wait()
      request.close()
    let replacement = compiled.createInferRequest()
    queue.attach(replacement, 1)
    replacement.startAsync()
    check queue.next(patience).get == 1
    replacement.wait()
    replacement.close()
    queue.close()

  test "copies of a queue share one closed state":
    let queue = newCompletionQueue(capacity = 1)
    let alias = queue
    alias.close()
    check queue.isClosed
    queue.close()

  test "a queue dropped while a request is running stays valid until the request goes":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileBusy()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    block:
      let queue = newCompletionQueue(capacity = 1)
      queue.attach(request, 3)
      request.startAsync()
    # The queue's last Nim reference is gone, but the running request still
    # holds the shared memory its callback writes into.
    request.wait()
    request.close()
