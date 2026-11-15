# r4 COMMON-002: dense MTP indexer allocation and short CLI validation

Status: Gate B passes on the supplied Windows Vulkan runs. All three allocation
smokes and five short CLI runs are OK; candidate startup evidence, real
speculative acceptance/carry coverage and work removal are confirmed. Proceed
to the two 256k wall runs, retaining default OFF. Long-context performance and
normal ABBA remain pending; no candidate speedup is established by this gate.

Source archive:
`20261004-150537-503-cli-vulkan-b11408-ctx32768-42c8bcd29b15.zip`.
It contains eight run directories and the complete five-run matrix
`20261004-150203-615-qwen38-r4-mtp-dense-indexer-check`.
Collection interval: 2026-10-04 14:58:46 through 15:06:19 JST.
The matrix reports Complete=true, StoppedEarly=false, finished/planned=5/5 and
OK/NonOK=5/0; all eight individual native exit codes are zero.

## Build, conditions and identity

Every run uses Vulkan b11408, embedded commit `e2deea70a`, Clang 20.1.8, with
BuildIdentity and RuntimeArtifactStatus Verified. All eight have the same CLI
SHA256 `406e37421b1efdfad2a6fdc50356f30404bef59bb57b6e3158d5d793db306741`
and runtime artifact digest
`04eb0847d003a55f562c59fd33fca8c298c20d072023c592f8241ffc8c59cdb6`.
The documentation-only checkout changes do not require a rebuild; retain this
manifest and binary/DLL set for the focused wall pair.

Target: Unsloth PLE16 UD-IQ3_XXS, 81,961,816,672 bytes. Draft: Unsloth Q8_0
MTP sidecar, 4,137,429,120 bytes. Use conditions.json ModelIdentity/
EffectiveCondition.Model for target identity: the generic result.json model
type/size fields in MTP runs describe the last-loaded draft, not the target.
Model SHA256 was not collected; paths, lengths and timestamps match across arms.

UMA label 96GB, context capacity 32768, f16 K/V, batch2048, ubatch1024, t4/tb4,
ngl999, CpuMoe0, flash-attention auto, fit/reasoning off, cache RAM0 and context
checkpoints0t. MoE legacy tile=1, GET_ROWS128x4=0, QSA union=1. All MTP ON runs
use DraftMax2 and DraftPMin0. Inherited experimental settings are cleared by the
matrix. A/B EffectiveCondition fields match except the intended environment
switches. The ordinary runs emit no `mtp_diag v=` records.

## Three allocation smokes

Each AllocationOnly run includes an 18-token short prompt and 32 output tokens;
it is not allocation without inference. They retain diagnostics OFF.

| Run ID suffix | MTP | Omission setting | Status / evidence | Accepted/generated draft |
|---|---|---|---|---:|
| 145846-885 / c6b4dbe4f0da | OFF | 1 | OK / MtpDisabled | N/A |
| 145924-003 / add5502ed7c1 | ON | 0 | OK / Verified, omitted=false | 13/34 |
| 150003-742 / c5a14636f961 | ON | 1 | OK / Verified, omitted=true | 13/34 |

Both MTP startups identify eligible layer48/ratio0. The draft's 64MiB attention
KV allocation remains in B, while A's additional 16MiB indexer KV allocation
is absent. Target 768MiB attention and 192MiB indexer KV buffer lines remain in
all runs. These are per-buffer startup sizes; the target-only printed memory
breakdown must not be treated as total target-plus-draft process memory.

## Five short runs

Input `mtp-short.txt` has 163 prompt tokens, with SHA256
`88083a2910b0de75fdfc23d73a7e87ce3db0cf5110bb616ae102841be34368d5`.
Each run generates 128 tokens with temperature0, top-k1, top-p0.8, seed1234
and ignore-eos. This is a short prompt at 32k capacity, not a full 32k input.

| Variant | MTP | Omission | Diagnostics | PP tok/s | TG tok/s | Accepted/generated draft |
|---|---|---|---|---:|---:|---:|
| control-mtp-off | OFF | Inactive (setting1) | off | 330.45 | 28.47 | N/A |
| A-normal | ON | OFF | off | 303.24 | 35.12 | 69/116 |
| B-normal | ON | ON | off | 300.06 | 34.91 | 69/116 |
| A-wall | ON | OFF | wall | 303.70 | 35.52 | 69/116 |
| B-wall | ON | ON | wall | 302.49 | 35.39 | 69/116 |

All four MTP ON rendered response bodies are identical after removing the CLI
banner, echoed prompt and timing/footer. Body UTF8 SHA256 is
`9af8bac14893768f940030b0bfae90f36b43d97d361e49404be530376d61aec5`.
This is a rendered-text comparison, not a saved token-ID/logit trace. Fixed
128-token output truncates the response at its budget; no completion of the
Japanese answer beyond that limit is claimed. MTP OFF's response differs;
that does not isolate the omission switch because both candidate arms use MTP
ON. Earlier native same-input A/B logit/hidden checks remain the numerical gate.

The MTP ON runs share draft acceptance 69/116=59.483%. A-wall and B-wall also
have exactly the same ordered 58-element accept_carry sequence:

| Accepted length | Meaning | Rounds in each wall arm |
|---|---|---:|
| 0 | Full draft rejection | 14 |
| 1 | Partial acceptance | 19 |
| 2 | Full acceptance | 25 |

Each wall arm records 116 draft_decode and 58 generation catchup_decode calls,
with matching carry/verification coverage. Thus the single short prompt covers
rejection, partial and full acceptance; another prompt is not required solely
to fill those branches.

## Diagnostics confirm bounded work removal

Both wall sidecars are Complete, with no Issues and no phase-alignment warning.
A has 3,546 end events and 34 unmatched-phase events; B has 3,074 and 28. These
include startup/warmup outside server prompt/generation intervals and are
retained as unknown, not invented into generation. Covered generation is
3.566423/3.578902 seconds (A/B), with approximate uncovered 0.008757/0.009768
seconds. This is CPU interval coverage, not GPU kernel duration.

| Generation scope | A calls / inclusive ms | B calls / inclusive ms |
|---|---:|---:|
| Draft layout | 174 / 1.593 | 0 / 0 |
| Draft pool_state | 174 / 0.425 | 0 / 0 |
| Draft seq_rm_indexer | 116 / 1.981 | 0 / 0 |
| Target layout | 58 / 0.820 | 58 / 1.034 |
| Target pool_state | 58 / 0.092 | 58 / 0.138 |
| Target seq_rm_indexer | 58 / 1.021 | 58 / 1.035 |

B has zero draft layout/pool_state/seq_rm_indexer events across prompt,
generation and unknown/startup phases. A's prompt draft layout/pool_state
each has one call. B retains draft attention/recurrent sequence removal and
target indexer/layout/pool work. This confirms the intended narrow omission;
the target path remains in service. Times above are inclusive/nested: do not
sum parent seq_rm with its children or interpret Vulkan dispatch CPU scopes as
GPU kernel time.

Normal TG changes from 35.12 to 34.91 tok/s (-0.60%) and PP from 303.24 to
300.06 (-1.05%). There is one ordinary run per arm, with millisecond-scale
short-prompt layout work. These differences establish neither a speedup nor a
repeatable regression. The reason to proceed to 256k is confirmed work removal
plus native/CLI correctness evidence, against the earlier 9.901-second dense
draft layout bottleneck, not an improvement in this short timing pair.

## Next: two 256k wall runs, then review

Use the existing verified binary/DLL set; no rebuild or manifest refresh is
needed for this documentation-only update. Run from the repository root:

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-mtp-dense-indexer-wall.psd1 -PlanOnly
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-mtp-dense-indexer-wall.psd1 -StopOnError
```

PlanOnly must show exactly A-wall then B-wall at context262144 and InputKey256k.
Both have MTP ON and diagnostics wall; only omission changes 0 to 1. They use
512 output tokens, temp0.2/top-p0.8/seed1234, f16, b2048/ub1024, t4/tb4,
cache RAM0/checkpoints0t and the same validated MoE/union controls. The plan
supplies and restores environment settings; do not enable extra profiling.

Return both reports and the matrix after this pair. Check Complete diagnostics,
zero B draft indexer/layout/pool events, retained target work, PP/TG and total
latency, acceptance, output and resources before approving ordinary 256k ABBA.
Long stochastic text differences alone are not a logit-equivalence result.
No sync pair, 128k expansion, ROCm build or overnight matrix is required yet.

Related: [implementation and gates](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md),
[native validation](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md#1450-windows-native-gate-complete),
[roadmap](ROADMAP.md).
