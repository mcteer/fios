// The former host installation was explicitly rejected. Never recreate native jobs.
console.error('Native Fios service installation is disabled. Use the OrbStack Fios Compose stack; see README.md.');
process.exitCode=1;
