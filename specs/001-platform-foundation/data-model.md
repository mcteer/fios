# Foundation inventory data

The Mini reads the most recent local observation for each configured host when the operator refreshes. The sampler atomically replaces a single file per host. The foundation has no history store.

| Field | Meaning and constraint |
| --- | --- |
| `Host.id` | Stable configured key, one of `fios-core`, `studio-a`, `studio-b`. Each appears exactly once. |
| `Host.hardware`, `Host.chip`, `Host.role`, `Host.configured_gb` | Inventory labels from configuration. The Mini is the 24 GB M4 Pro control plane. Both Studios are 256 GB M3 Ultra inference workers. |
| `Observation.version` | Integer 1. The reader accepts exactly the six observation fields listed here. |
| `Observation.node` | Matches the configured ID whose sample is being read. |
| `Observation.sampled_at` | Integer Unix seconds from 1 through the time of the read. |
| `Observation.memory_bytes` | Physical memory in bytes, integer from 1 through 2⁶⁰. |
| `Observation.logical_cpus` | Integer from 1 through 65,536. |
| `Observation.load_1m` | Finite one-minute load average between 0 and 1,000,000,000 inclusive. Boolean values are invalid for all numeric fields. |
| `Host.state` | Missing file → awaiting. Invalid file → invalid. Valid sample aged 0–30 seconds inclusive → reporting. Older valid sample → stale. Recompute on every read. |
| `Host.observation` | Include the latest accepted values in reporting and stale states. Return null for awaiting and invalid. |
| `Operator.role` | Trusted local bootstrap reads resolve to admin. Only admin has the inventory.read permission. |

A sample is a regular file of at most 4096 bytes. The reader rejects symlinks, extra fields and values outside the stated limits. A new valid sample can restore reporting after any prior state. Only reporting hosts contribute to the count. A host's physical memory and one-minute load do not establish its schedulable capacity.
