# r5 Vulkan MoE tile selection: upstream revert investigation (2026-10-09)

## Decision

**UPSTREAMED / RETIRE** the r4-only `GGML_VK_MOE_LEGACY_TILE_SELECTION` selector switch for **r5**. The pinned r5 upstream already reverted the per-expert tile heuristic introduced in upstream PR #29182. For the selection expression, the r5 default is the same as the **legacy ON** arm in the measured r4 diagnostic.

Do **not** port the r4 diagnostic branch, its environment controls or its tile logger as a performance patch. Keep the r4 historical experiment intact. Revisit only if a future upstream change reintroduces a regression or a separate multi-model diagnostic warrants a new switch. This is a source-level identity of the selector inputs, **not** proof of kernel-wide equivalence or proof that every percentage point in cross-build timing is due to this change.

## Upstream history and evidence

| Date (2026) | Reference | What changed |
|---|---|---|
| Sep 29 | [PR #29182](https://github.com/ggml-org/llama.cpp/pull/29182), [`94a0ae3e7298`](https://github.com/ggml-org/llama.cpp/commit/94a0ae3e7298127b74d5b31370e83a1b4f143070) | Changed Vulkan quantized MoE `MUL_MAT_ID` selector/alignment input from `nei1` (total tokens) to `n_per_expert = CEIL_DIV(nei0 * nei1, n_as)`. |
| Oct 3 | [AMD regression issue #29892](https://github.com/ggml-org/llama.cpp/issues/29892) | Reported about 12% RDNA4 RX 9070 XT PP regression for a different MoE workload; TG unaffected in reported tests. This is corroborating external evidence, not Evo-X2 data. |
| Oct 5 | [PR #29936](https://github.com/ggml-org/llama.cpp/pull/29936), [`3c9e747f7e8b`](https://github.com/ggml-org/llama.cpp/commit/3c9e747f7e8b456d81ee66ae679e943213fb7f7d) | **Merged full revert** of the three selector/alignment expressions to use `nei1`. The discussion also documents major Intel Arc Pro B70 MoE PP regression. The final revert is not limited to Intel. |
| Oct 9 | r5 pinned upstream `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b` | Contains the reverted `nei1` logic; the local r4 diagnostic environment flag is not part of the clean inference source. |

## Exact code path checked

File: `ggml/src/ggml-vulkan/ggml-vulkan.cpp`, function
`ggml_vk_mul_mat_id_q_f16()`.

At the old r4 clean base (embedded b11372 / `94b877457`), the critical portion was:

```cpp
const uint32_t n_per_expert = (uint32_t) CEIL_DIV(nei0 * nei1, n_as);
const uint32_t kpad = quantize_y ? 0 :
    ggml_vk_align_size(ne10,
        ggml_vk_guess_matmul_pipeline_align_map(ctx, *mmp_map, ne01, n_per_expert, true));
const bool aligned = !quantize_y && ne10 == kpad && ne01 > 8 && n_per_expert > 8;
vk_pipeline pipeline = ggml_vk_guess_matmul_pipeline_map(ctx, *mmp_map, ne01, n_per_expert, aligned, true);
```

The r4 local opt-in at `c81b8bf78f47dcaefd47a2f49f72ec4035e1d874` introduced:

```cpp
const uint32_t tile_n =
    ctx->device->moe_legacy_tile_selection ? (uint32_t) nei1 : n_per_expert;
```

Then used `tile_n` for the alignment map, `aligned` test, and matmul-pipeline map. `GGML_VK_MOE_LEGACY_TILE_SELECTION=1` selected `nei1`; default OFF preserved old upstream behavior.

In **r5 pinned upstream**, all three decisions use total-token `nei1` directly:

```cpp
const uint32_t kpad = quantize_y ? 0 :
    ggml_vk_align_size(ne10,
        ggml_vk_guess_matmul_pipeline_align_map(ctx, *mmp_map, ne01, nei1, true));
const bool aligned = !quantize_y && ne10 == kpad && ne01 > 8 && nei1 > 8;
vk_pipeline pipeline = ggml_vk_guess_matmul_pipeline_map(ctx, *mmp_map, ne01, nei1, aligned, true);
```

This matches the three relevant *selection expressions* in r4 legacy-ON. The r5 clean build has no local selector switch or diagnostic log; no special environment variable is needed to get this default. Dispatch grid and expert routing are distinct from the selector; no claim is made that every shader or dispatch detail is otherwise unchanged across upstream versions.

## Evo-X2 evidence and interpretation

r4 [same-binary normal ABBA](R4-MOE-TILE-AB-2026-10-03.md) at 64k, Original Unsloth, MTP OFF, 61,789 prompt tokens, context 65,536, batch/ubatch 2048/1024, Radeon 8060S:

| Selector | Mean PP, tok/s | Mean TG, tok/s | Notes |
|---|---:|---:|---|
| `n_per_expert` (upstream then, A1/A2) | 248.475 | 25.195 | old r4 default |
| `nei1` (legacy ON, B1/B2) | **268.985** | 24.565 | local diagnostic `=1`; **PP +8.25%** |

The r4 GPU profile showed PP MoE GPU operator time **63.933 → 47.807 seconds (-25.22%)**, while PP Flash Attention was nearly unchanged (108.658 → 108.654 s). The r4 A/B is strong causal evidence for this local selector difference *within that tested binary/workload*. TG in the 128-token ABBA varied between runs and cannot establish a reliable change.

The [r5 clean baseline and 26H2 control](R5-CLEAN-BASELINE-VALIDATION-2026-10-09.md) adds a useful but non-identical cross-build comparison:

| Build/environment | Vulkan 64k PP tok/s |
|---|---:|
| r4 clean, old Windows | 248.38 |
| r4 clean executable replay, Windows 11 26H2 | 248.18 |
| r4 experimental legacy selector ON, historical r4 ABBA mean | 268.985 |
| r5 clean, Windows 11 26H2 | **269.24** |

r4 old-vs-new Windows PP differs by approximately -0.08%; r4→r5 on the **same 26H2 OS** is **+8.49%** PP. The r5 result is close to r4 legacy-ON and the r5 code visibly restores its selector logic. Thus the upstream revert is the **leading explanation** of the recovered 64k Vulkan PP, without strictly isolating all intervening upstream code/build changes.

The r5 clean 128k/256k run also completed, but no matched same-binary long-context MoE selector A/B was performed on r5. Avoid treating the observed 128k/256k r4→r5 differences as fully attributed to the revert. ROCm performance changes require a different explanation because this selector is in Vulkan-only code.

## Follow-up and boundaries

1. **No r5 port / no new MoE tile build or A/B required now.** Mark the r4 selector patch retired for r5 while retaining the archived r4 diagnostic and metrics.
2. Preserve the clean r5 binaries and fixed benchmark metadata; no inference-source modification was made by this investigation.
3. Keep **COMMON-001 split PLE16 loader compatibility** and **VULKAN-002 grouped QSA union** separate from MoE selection. The MoE finding does not supply either change.
4. Check upstream source again at the next refresh before retaining the retirement status; the selection heuristic could change again.
5. If publishing, distinguish the within-r4 same-binary +8.25% MoE switch effect from the across-build / same-OS r4→r5 +8.49% PP difference.

Sources: [r4 MoE ABBA](R4-MOE-TILE-AB-2026-10-03.md),
[r5 64k/128k/256k baseline](R5-CLEAN-BASELINE-VALIDATION-2026-10-09.md),
[upstream revert commit](https://github.com/ggml-org/llama.cpp/commit/3c9e747f7e8b456d81ee66ae679e943213fb7f7d).
