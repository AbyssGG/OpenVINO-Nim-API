# SPDX-License-Identifier: Apache-2.0

## The only code that runs on an OpenVINO worker thread.
##
## `ov_infer_request_set_callback` makes OpenVINO call a C function on a thread
## Nim did not create. Anything that touches the Nim heap, raises, or reaches a
## `ref`, `string` or `seq` there is undefined behaviour. This module therefore
## holds only plain shared-memory types and procedures that call the operating
## system directly: a mutex, a condition variable and a fixed ring of pointers.
## `nimble lint` enforces that no allocation, string or exception construct
## appears in it. See `docs/decisions/0003-async-completion.md`.
##
## Stack traces, line traces and runtime checks are off for the whole module,
## so that no Nim runtime bookkeeping runs on the foreign thread either.

import ../raw/infer_request

{.push raises: [], gcsafe, stackTrace: off, lineTrace: off, checks: off.}

when defined(windows):
  type
    OsLock {.importc: "CRITICAL_SECTION", header: "<windows.h>",
             final, pure, byref.} = object
    OsCond {.importc: "RTL_CONDITION_VARIABLE", header: "<windows.h>",
             byref.} = object

  proc osInitLock(lock: var OsLock) {.importc: "InitializeCriticalSection",
                                      header: "<windows.h>".}
  proc osDeinitLock(lock: var OsLock) {.importc: "DeleteCriticalSection",
                                        header: "<windows.h>".}
  proc osAcquire(lock: var OsLock) {.importc: "EnterCriticalSection",
                                     header: "<windows.h>".}
  proc osRelease(lock: var OsLock) {.importc: "LeaveCriticalSection",
                                     header: "<windows.h>".}
  proc osInitCond(cond: var OsCond) {.importc: "InitializeConditionVariable",
                                      header: "<windows.h>".}
  proc osSignal(cond: var OsCond) {.importc: "WakeConditionVariable",
                                    header: "<windows.h>".}
  proc osSleepCond(cond: var OsCond; lock: var OsLock;
                   milliseconds: uint32): int32
    {.importc: "SleepConditionVariableCS", header: "<windows.h>".}

  proc osDeinitCond(cond: var OsCond) =
    ## Windows condition variables need no teardown.
    discard

  proc osWaitMilliseconds(cond: var OsCond; lock: var OsLock;
                          milliseconds: int64) =
    ## Waits at most `milliseconds`, which the caller keeps below one hour.
    discard osSleepCond(cond, lock, uint32(milliseconds))
else:
  type
    OsLock {.importc: "pthread_mutex_t", header: "<pthread.h>",
             final, pure, byref.} = object
      when defined(linux) and defined(amd64):
        abi: array[40 div sizeof(clong), clong]
    OsCond {.importc: "pthread_cond_t", header: "<pthread.h>",
             final, pure, byref.} = object
      when defined(linux) and defined(amd64):
        abi: array[48 div sizeof(clonglong), clonglong]
    OsTimespec {.importc: "struct timespec", header: "<time.h>",
                 final, pure.} = object
      tv_sec: clong
      tv_nsec: clong

  var CLOCK_REALTIME {.importc, header: "<time.h>".}: cint

  proc osInitLockAux(lock: var OsLock; attributes: pointer): cint
    {.importc: "pthread_mutex_init", header: "<pthread.h>".}
  proc osDeinitLockAux(lock: var OsLock): cint
    {.importc: "pthread_mutex_destroy", header: "<pthread.h>".}
  proc osAcquireAux(lock: var OsLock): cint
    {.importc: "pthread_mutex_lock", header: "<pthread.h>".}
  proc osReleaseAux(lock: var OsLock): cint
    {.importc: "pthread_mutex_unlock", header: "<pthread.h>".}
  proc osInitCondAux(cond: var OsCond; attributes: pointer): cint
    {.importc: "pthread_cond_init", header: "<pthread.h>".}
  proc osDeinitCondAux(cond: var OsCond): cint
    {.importc: "pthread_cond_destroy", header: "<pthread.h>".}
  proc osSignalAux(cond: var OsCond): cint
    {.importc: "pthread_cond_signal", header: "<pthread.h>".}
  proc osTimedWait(cond: var OsCond; lock: var OsLock;
                   deadline: ptr OsTimespec): cint
    {.importc: "pthread_cond_timedwait", header: "<pthread.h>".}
  proc osClockGetTime(clock: cint; now: ptr OsTimespec): cint
    {.importc: "clock_gettime", header: "<time.h>".}

  proc osInitLock(lock: var OsLock) = discard osInitLockAux(lock, nil)
  proc osDeinitLock(lock: var OsLock) = discard osDeinitLockAux(lock)
  proc osAcquire(lock: var OsLock) = discard osAcquireAux(lock)
  proc osRelease(lock: var OsLock) = discard osReleaseAux(lock)
  proc osInitCond(cond: var OsCond) = discard osInitCondAux(cond, nil)
  proc osDeinitCond(cond: var OsCond) = discard osDeinitCondAux(cond)
  proc osSignal(cond: var OsCond) = discard osSignalAux(cond)

  proc osWaitMilliseconds(cond: var OsCond; lock: var OsLock;
                          milliseconds: int64) =
    ## Waits at most `milliseconds`, which the caller keeps below one hour.
    ## The condition variable uses the default realtime clock, so the
    ## deadline is computed on that clock.
    var deadline: OsTimespec
    discard osClockGetTime(CLOCK_REALTIME, addr deadline)
    let nanoseconds = int64(deadline.tv_nsec) +
      (milliseconds mod 1000) * 1_000_000
    deadline.tv_sec = deadline.tv_sec + clong(milliseconds div 1000) +
      clong(nanoseconds div 1_000_000_000)
    deadline.tv_nsec = clong(nanoseconds mod 1_000_000_000)
    discard osTimedWait(cond, lock, addr deadline)

type
  QueueShared* = object
    ## The shared state of one `CompletionQueue`. Allocated with
    ## `allocShared0`; every field except `references` is protected by
    ## `lock`.
    lock: OsLock
    cond: OsCond
    ring: ptr UncheckedArray[ptr RequestBox]
      ## Completed requests not yet returned by `next`, oldest first.
    capacity*: int
    head: int
    count: int
    attached*: int
      ## Requests currently attached. Never above `capacity`.
    closed*: bool
      ## Set when the owner closes the queue; completions are then dropped.
    references: int
      ## One for the queue owner plus one per attached request. Changed only
      ## under `lock`; the memory is released when it reaches zero.

  RequestBox* = object
    ## Shared-memory owner of one `ov_infer_request_t`, allocated with
    ## `allocShared0` so that its address never changes.
    ##
    ## OpenVINO keeps a pointer to `callback`, which is why it lives here and
    ## why the box is released only after the request.
    native*: ptr ov_infer_request_t
    callback*: ov_callback_t
    queue*: ptr QueueShared
      ## Set before the callback is installed and cleared only after the
      ## request is freed, so the trampoline may read it without the lock.
    id*: int
    queued: bool
      ## Whether the ring already holds this box. Protected by the queue's
      ## lock. Keeps each request to at most one entry, which is what bounds
      ## the ring by the number of attached requests.
    started*: bool
      ## Whether `start_async` ever succeeded. Owner thread only.

proc completionTrampoline*(args: pointer) {.cdecl.} =
  ## The callback installed on every attached request. Runs on an OpenVINO
  ## thread.
  ##
  ## Takes the lock, appends the box to the ring unless it is already there or
  ## the queue is closed, wakes one waiter, and releases the lock. Nothing
  ## else.
  # invariant: `args` is the `RequestBox` that installed this callback. The box
  # outlives the request (it is freed only after `ov_infer_request_free`, which
  # waits for a running callback), so the pointer is valid here.
  let box = cast[ptr RequestBox](args)
  let queue = box.queue
  if queue == nil:
    return
  osAcquire(queue.lock)
  if not queue.closed and not box.queued and queue.count < queue.capacity:
    queue.ring[(queue.head + queue.count) mod queue.capacity] = box
    queue.count = queue.count + 1
    box.queued = true
    osSignal(queue.cond)
  osRelease(queue.lock)

proc initQueueShared*(queue: ptr QueueShared;
                      ring: ptr UncheckedArray[ptr RequestBox];
                      capacity: int) =
  ## Initialises zeroed shared memory as an open queue owned by one
  ## reference.
  osInitLock(queue.lock)
  osInitCond(queue.cond)
  queue.ring = ring
  queue.capacity = capacity
  queue.references = 1

proc acquireQueue*(queue: ptr QueueShared) =
  osAcquire(queue.lock)

proc releaseQueue*(queue: ptr QueueShared) =
  osRelease(queue.lock)

proc addReference*(queue: ptr QueueShared) =
  ## Adds a reference. Call with the lock held.
  queue.references = queue.references + 1

proc dropReference*(queue: ptr QueueShared): ptr UncheckedArray[
    ptr RequestBox] =
  ## Drops one reference. When it was the last one, tears the queue down and
  ## returns the ring so the caller can release both allocations; otherwise
  ## returns `nil`. Call **without** the lock held.
  osAcquire(queue.lock)
  queue.references = queue.references - 1
  let last = queue.references == 0
  osRelease(queue.lock)
  if not last:
    return nil
  osDeinitCond(queue.cond)
  osDeinitLock(queue.lock)
  queue.ring

proc pendingCount*(queue: ptr QueueShared): int =
  ## Completions not yet returned by `next`. Call with the lock held.
  queue.count

proc popCompletion*(queue: ptr QueueShared): int =
  ## Removes the oldest completion and returns its request id. Call with the
  ## lock held and only when `pendingCount` is positive.
  let box = queue.ring[queue.head]
  queue.head = (queue.head + 1) mod queue.capacity
  queue.count = queue.count - 1
  box.queued = false
  box.id

proc waitForCompletion*(queue: ptr QueueShared; milliseconds: int64) =
  ## Waits on the condition variable for at most `milliseconds`. Call with
  ## the lock held; it is held again on return. May wake early.
  osWaitMilliseconds(queue.cond, queue.lock, milliseconds)

proc removeEntries*(queue: ptr QueueShared; box: ptr RequestBox) =
  ## Removes `box` from the ring, keeping the order of the others, and
  ## counts it as detached. Call with the lock held.
  var kept = 0
  for offset in 0 ..< queue.count:
    let entry = queue.ring[(queue.head + offset) mod queue.capacity]
    if entry != box:
      queue.ring[(queue.head + kept) mod queue.capacity] = entry
      kept = kept + 1
  queue.count = kept
  box.queued = false
  queue.attached = queue.attached - 1

{.pop.}
