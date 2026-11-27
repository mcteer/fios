# fios constitution

Initial project conventions drafted on 2026-11-27. The repository's AGENTS.md governs engineering work. This project applies those instructions to three boundaries.

1. Operators can distinguish configured hardware, observed capacity and reservations. An absent or expired measurement gives the scheduler zero capacity to allocate.
2. Only the control plane grants authority. A model can propose a typed action. The authenticated actor, resource owner, job lease and role determine whether it runs. Content publication rules apply to every role.
3. Start on the owner's trusted Mini. Every expansion of the trust boundary needs its own spec, tests and recovery procedure. Internet access comes last. A local process with administrator privileges over Docker or the host is inside the bootstrap trust boundary.

Work in numbered feature directories beneath `specs/`. Specify observable journeys, investigate primary sources, record design choices and tasks, then implement and verify each slice. Cite measured evidence in the task list. Keep unmeasured candidates and hardware hypotheses explicit.
