# Scoped native identity header route refusal

The current process-instance, original request correlation and handoff protocol
supports `POST /v1/chat/completions`. Preparation identity already rejected
other routes. The optional router increment now parses the other three fixed
headers before dispatch and refuses their use outside the supported route with
`400 invalid_native_identity_route`. Malformed identity remains a400 error.
It never silently treats such a request as a process-bound modality request.

Ordinary requests without these headers retain the existing native routes and
selection behavior. The supported chat route retains original exact target,
process epoch, correlation, preparation and handoff checks. No numerical engine,
model setting, route activation or installed server changes.

This refusal does not complete FR004, extend positive native admission to other
modalities, or reduce their acceptance scope. Full enabled-route/all-client
ownership, positive completion and non-preemptive admission remain required.
The patch keeps the existing serving guard disabled and coverage unknown.

The `current-native-ingress.py --route-guards` mode uses an empty private model
catalog and deliberately absent fixture IDs. Twelve endpoint paths cover text,
embeddings, image, audio, video and3D interfaces. It tests stale/current epoch
headers, non-chat correlation/handoff headers and ordinary header-free refusal.
58 refusal POSTs cannot invoke a registered model. Local HTTP-reference cleanup
and zero model mutations remain local observations, never native terminality.
It does not test positive modality behavior, a real slow response or physical
backend completion. A separate genuine parent run must fail the new assertion;
the changed candidate and existing chat cases must pass before qualification.
