# Existing MLX C binding and event-enabled SDK composition

This source qualification rebuilds the existing MLX C binding, not an inference
engine. The selected binding source is56b2d39fc831f2c0eb5bb94d82ef7191f7b31fa6
plus the existing three-line global-scale compatibility patch in `fast.cpp` and
`ops.cpp`. It matches the previously retained binding source. No math, model,
ID, routing, backend selection or installed configuration changes.

The private CMake build uses the exact event-enabled SDK library4fc2c5d3… and
headers, Apple SDK27.2, arm64/apple-m1, deployment target26.2, two compiler jobs,
shared bindings and no examples/network dependency fetching. All132 selected
binding source files and411 selected SDK-stage inputs remain unchanged across
configure/build/private staging. The resulting library is25dfeb4f…; replacing
only that library preserves the remaining445 files of the existing446-file
serving stage, including its historical revision stamp. The stamp is not proof
of the new SDK/binding composition; separate receipts identify that composition.

`check-platform-current-mlxc.py` compiles the fixed C fixture in debug and
optimized modes. Each child denies network and has an eight-second deadline.
It verifies both exact mapped library paths, evaluates a genuine CPU scalar-add
graph, checks a genuine invalid-reshape error through the C error handler and
releases its arrays/stream. Compiler-selected C headers, compiler, fixture,
libraries and selected system stub are hashed before/after. Both old and rebuilt
bindings pass these controls with the same SDK, so no old binding runtime bug is
claimed. No model, GPU dispatch or native ownership authority is tested.

The existing C++ checker adds explicit `--sdk-request-events` after
`--owner-capture-refusal`. It reconstructs the exact eight-path SDK composition
including both CPU and command-buffer event overlays, before compiling its
existing real CPU callback/error controls in Debug/ReleaseFast. It refuses the
old seven-path selection rather than silently admitting new source. The new
receipt uses a distinct event-SDK scope and records both patch hashes. It does
not register production observers or run a model/Metal shader.

This event-SDK CPU compatibility receipt remains outside model prerequisites.
The current model-prerequisite reader refuses it, including the actual3736ed55
native source base; no historical release-base label is substituted. Old immutable
receipts retain their original checker digest. A changed checker does not renew
those receipts or grant another model request. No sixth real inference plan/POST
is authorized or created by these checks.

Full native builds and private empty-model checks must qualify the serving
composition separately. None of these selected source/header records proves
whole-native/publisher provenance, all-client coverage, device terminality,
atomic admission, installed acceptance or activation. Whole tasks remain39/55.
