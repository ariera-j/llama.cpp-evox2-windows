# r4 VULKAN-002: grouped-union source review and scoped port plan

Status: source review complete, adapted implementation pending. No grouped-union
code is added to r4 by this review. The next implementation should be opt-in and
preserve the existing dense/per-row sparse attention fallbacks.

## Fixed source identities

- r4 reviewed HEAD: `569d9f77a94d29471798704bf13b6051fdee702a` on
  `r4/upstream-refresh-20261002`; upstream base remains `bed0a856...`.
- Historical r2 source: `main` pinned for this review to
  `23c316fb5af67da74e614af4a7453fba9ae46189`.
- r2 introduction commit located by commit search:
  `8f6e361dc01da153affcdddac74205c425832c17` (grouped-union prefill).
- Frozen r3 `0a93fcbb...` intentionally lacks this optimization; do not use r3
  as the donor or restore COMMON-004/005 as part of this port.

The cached-gather 128x4 gate is closed without promotion. Its switch stays OFF.
See [R4-GET-ROWS-128X4-AB-2026-10-03.md](R4-GET-ROWS-128X4-AB-2026-10-03.md).

## What r2 actually does

Primary donor locations, at the pinned r2 source:

- `ggml/src/ggml-vulkan/ggml-vulkan.cpp`: `ggml_vk_qsa_union()`, the early call
  in `ggml_vk_flash_attn()`, pipeline creation and union/count scratch handling.
- `vulkan-shaders/qsa_union.comp`: sorted/deduplicated union of selected token
  cell ids, using a reusable 16 KiB bitmap over 131072-position ranges.
- `vulkan-shaders/qsa_gather.comp`: gather K/V per KV head and preserve each
  query's original additive/causal mask at the union positions.
- `vulkan-shaders/flash_attn_base.glsl`: dynamic KV length from the device-written
  rounded union count, without reading the count back to choose a CPU dispatch.

Queries are partitioned into groups of at most 64. For each group:

1. Union the token ids selected by its queries. Ignore negative/out-of-KV ids.
2. Gather each KV head once into compact f16 K/V. Gather the original mask for
   every query, using -inf for padding. An id selected by another query therefore
   does not become visible to this query.
3. Run the existing tuned FA over the compact union. Its runtime KV length is
   the union count rounded up to 256, with at least 256 padding slots.

The scratch allocation uses a conservative maximum union size, but FA's runtime
loop uses the actual count. Scratch K/V is reused across groups with barriers;
union lists and count slots are per group. Statistics describe the last recorded
attention op rather than aggregate runtime work across all layers.

Historical eligibility includes Q count 2..4096, f32 Q/output, f16 K/V/mask,
single stream, compatible heads/strides, no sinks/ALiBi/softcap, KV at least
32768 by default and at most 262144, and sufficient subgroup/shared-memory/
descriptor/dispatch resources. One-query decode takes the existing path.

## What refreshed r4 already provides

`ggml_vk_flash_attn()` compacts finite mask entries per row using
`flash_attn_sparse_compact.comp`, then gathers K/V inside sparse FA shaders.
The source eligibility ends with:

```cpp
(gqa_ratio > 1 || (tuning_params.path == FA_SCALAR && N == 1))
```

The GQA transformation requires original query count `N <= 8`. Thus the observed
1024/349-query PP shapes have `gqa_ratio == 1` and cannot use this per-row sparse
route. Dense FA still has its mask-tile optimization, so the missing route is
specifically shared grouped-union PP, not all sparse/masked attention support.

| Concern | r2 donor | r4 | Port decision |
|---|---|---|---|
| PP selection | Explicit selected token ids | Pool-domain top-k expanded to cell ids, then scatter mask | Expose final token ids as optional FA metadata |
| Long PP attention | 64-query union, compact K/V/mask, dynamic length | Dense/tile-mask path for 1024/349 queries | Add grouped-union before existing dispatch |
| Short query/decode | Union declines for one query | Existing per-row sparse/GQA support | Preserve unchanged |
| Flag bit 16 | Dynamic KV count | USE_SPARSE index-list mode | Allocate a separate flag (proposed bit 32) |
| Descriptor binding 7 | Union count buffer | Sparse index buffer | Interpret by mutually exclusive flags; never reinterpret index lists as counts |
| FA shader/type code | Older pipeline/type definitions | Updated shader types, gathers, precision and tuning | Add dynamic-count behavior to r4 shaders; retain r4 implementation |

Blind cherry-picking the r2 backend or replacing its base shader would overwrite
new upstream work and collide with flag/descriptor meanings. Copy only the
union/gather algorithm and adapt its interfaces to r4.

## Correct selection tensor for the port

`src/models/qwen4exp.cpp`, `build_qsa_sel()`:

1. `top_k` selects pooled rows; these are **pool ids**, not KV token cell ids.
2. GET_ROWS of `pool_idxs` expands the pools into cell ids and concatenates
   incomplete-tail ids.
3. Visibility handling remaps dead slots to unique dump rows `n_kv + slot`,
   preventing duplicate writes when scattering the selection mask.
4. The resulting i32 `sel_idx` is the appropriate union metadata. Keep ids
   `0 <= id < n_kv`; the union shader must exclude dump/sentinel rows.

Use the **final remapped** tensor, not the early pool top-k or pre-remap ids.
Preserve the current mask scatter plus causal-mask addition; it remains the
authoritative per-query visibility/bias. Normal K/V cache addressing is unchanged.

With kpool=4 and 512 selected pools, the metadata has up to 2048 pool-member
slots plus three tail slots. Do not hardcode 2048 or assume ids are positional,
sorted or contiguous. Cell editing, shared cells, padding and incomplete pools
must keep their current selection semantics. A conservative union that contains
extra original-mask-invisible cells remains correct but can reduce the benefit.

## Scoped implementation sequence

1. Add a typed optional FA selected-cell metadata setter (src[5], separate from
   the existing src[4] sinks). Keep op_params[4] / n_kv_max and precision intact.
   This metadata is an optimization hint: the mask still defines the operator.
   Its contract must require that the ids cover every finite mask position per
   query (a superset is allowed); incomplete metadata would omit valid attention
   terms. The model builder supplies this guarantee; absent/unsupported hints
   fall back. Correctness fixtures must construct mask and ids consistently.
2. Return the final remapped ids alongside the mask from qwen4exp's local QSA
   builder. Pass them explicitly through `build_attn_qsa()` and an optional
   `build_attn_mha()` argument to the FA node. Default null for other callers;
   no model-wide persistent mutable tensor pointer.
3. Port/register qsa_union and qsa_gather, with capability/shape/stride/range
   guards and scratch/count ownership adapted to current Vulkan context types.
   Start with group=64 and the historical KV threshold 32768; no tuning sweep.
4. Add dynamic-count flag bit 32 to r4 FA initialization, with sparse bit 16
   unchanged and mutually exclusive. Binding 7 can hold counts only in union
   mode, indices only in sparse mode. Preserve r4 scalar/CM1/CM2 code, datatype
   specializations, F32 accumulation, mask handling and output layout.
5. Add early opt-in union dispatch to current FA. Never enlarge the existing
   per-row sparse predicate to multi-query tiles: queries can select different
   rows. Keep fallback for unsupported inputs/devices and one-query decode.
6. Audit graph cloning/debug helpers and source-dependency handling so optional
   metadata survives scheduling/reuse and cannot be freed before FA. Audit the
   existing qwen4exp graph fusion/protected-node rules before changing them.
7. Add targeted correctness tests, then separate build/profile/normal matrix
   plans with GET_ROWS 128x4 OFF and legacy MoE fixed. Diagnostic activation and
   fallback logs should be bounded; normal runs must avoid stats readback costs.

This crosses model graph, ggml metadata and Vulkan code; it is larger than the
closed GET_ROWS patch but need not alter pool storage, selection/scoring, ROCm
algorithms, model loading, MTP or upstream base. Before benchmark acceptance,
review count-buffer lifetime, group reuse barriers, graph reuse and maximum
scratch/descriptor bounds. Do not publish an unconditional speed expectation.

## Evidence that PP is the useful target

The already supplied b11387 Original/legacy-MoE 64k profile can be reused to
assess target cost without running another baseline. In its OFF run, excluding
two warmup blocks, the 61 PP timing blocks sum to:

| Profile GPU PP component | Time |
|---|---:|
| All GPU operators | 231.50918 s |
| FLASH_ATTN_EXT | 108.917465 s |
| FA share of GPU PP total | 47.05% |

The last full ubatch has Q `(256,1024,24,1)`, K/V `(256,61440,2,1)`; the tail
has Q `(256,349,24,1)`, K/V `(256,61952,2,1)`. These are 16 groups of 64 and
six groups (five of 64 plus 29), respectively. This confirms shape eligibility
for the planned route after metadata wiring, not a measured speedup.

Existing historical comparisons remain secondary context: r2 long-context PP
222.77/177.01 tok/s at 128k/256k versus recorded r4 COMMON-001 PLE16 legacy-MoE
178.99/132.99. Builds/selection algorithms differ; do not attribute the whole
gap to grouped-union or require an adapted r4 candidate to reproduce r2 values.

## Validation and measurement gates

- Union list tests: shuffled/duplicate ids, final dump sentinels, invalid ids,
  incomplete tail, last partial query group, and ids at/above 131072 through
  262143. High positions must survive the bitmap range loop.
- Gather/count tests: empty and tiny union padding, rounded lengths, bounded
  scratch, per-head source strides and descriptor alignment, exact preservation
  of gathered K/V and per-query finite/-inf masks.
- FA tests against the reference mask computation: query counts 2/63/64/65,
  349 and 1024; f32 accumulation; different selections per query, causal masking,
  duplicate ids and high KV positions. Use FA numerical tolerances, not bitwise
  equality of floating accumulation. Empty/all-masked behavior must match the
  existing operator's convention.
- Fallback tests: absent metadata, decode Q=1, threshold boundary, multi-stream,
  unsupported dtype/stride, sinks/bias/softcap and device/scratch limits.
  Existing sparse/decode and other-backend behavior must remain valid.
- Windows build + dedicated GPU correctness first. Then 64k Original/PLE16
  execution, OFF/ON with the same binary. Verify activation/decline evidence;
  an OFF/ON comparison in which both fall back is not an optimization test.
- Use 128k/256k as primary PP value tests. Profile the **whole** FA operator,
  including union scan, gather and barriers, plus GPU total. Logger-OFF normal
  matched runs decide throughput. Keep MoE and GET_ROWS switches fixed; monitor
  TG and memory/scratch use and stop on regression or correctness failure.

No r4 grouped-union code, GPU test or speed result is claimed by this source
review. The next step is the adapted opt-in implementation in the order above.
