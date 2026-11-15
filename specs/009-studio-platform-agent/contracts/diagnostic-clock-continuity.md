# Diagnostic clock continuity across rejected replies

Primary-request and independent backend diagnostic caches record the local
completion clock before validating a reply. A rejected replay or malformed
sample may make the view unavailable, but cannot erase that observed local
time. A subsequent local clock rollback permanently fences that cache.

The local clock checkpoint is separate from the accepted native sequence,
capture time, peer identity and retained uncertainty. Rejected replies do not
advance those native checkpoints. A later valid reply with forward local time
can refresh the view against its original native checkpoint; rollback cannot.
Invalid out-of-range local timestamps remain unavailable and are not stored.

The outer `NativeControlDiagnostics` already maintains this local-clock rule.
This increment makes its two independently tested child caches obey the same
rule, rather than relying on their caller to catch rollback. It does not claim
an existing public admission bypass. Both views remain unknown coverage and
non-authoritative; no native inference, lease or journal ownership is released.

The failing-first cases accept sequence2 at local1000, reject its replay at
local2000, then submit sequence3 at local1001. Both original caches incorrectly
publish that last reply. The corrected caches fence and retain uncertainty.
Independent forward-time controls accept sequence3 at local2001, proving that
the rejected replay did not advance native sequence/time. See validation for
Debug/optimized and complete mock-suite evidence.
