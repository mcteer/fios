# Plan

Keep Express/React and the existing signed HttpOnly same-site browser session. Make session initialization automatic; remove the login form, password validation and logout UI. Update existing smoke/deployment clients and browser/API regressions. Existing private environment values are left intact; the workspace password becomes unused. No inference, native lifecycle or cluster changes.

The operator request supersedes the prior interface-password requirement. Isolate this correction from spec009 on its own branch and PR targeting main.
