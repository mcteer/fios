    private func launch(args: [String], options: ServerOptions) {
        do { try GenerationDefaultsFile.migrate(options) }
        catch {
            lastError = "Could not save generation defaults: \(error.localizedDescription)"
            status = .error(lastError)
            return
        }
        port = options.port
        api.host = options.host
        status = .starting
        lastError = ""
        clearServerLog()

        // Reap orphaned mlx-serve processes still bound to our port (e.g. left
        // behind after a crash). We only target processes whose command name is
        // `mlx-serve` so we never kill an unrelated app that happens to be on
        // the port.
        killOrphanedServers(on: port)

    }
    private func killOrphanedServers(on port: UInt16) {
        let pids = pidsListening(on: port)
        let myPid = ProcessInfo.processInfo.processIdentifier
        for pid in pids where pid != myPid {
            guard processName(pid: pid).hasPrefix("mlx-serve") else { continue }
            kill(pid, SIGTERM)
            if !waitForExit(pid) {
                // A large resident model can take seconds to tear down after SIGKILL too;
                // launching before it is gone fails the new server's port check.
                kill(pid, SIGKILL)
                _ = waitForExit(pid)
            }
        }
    }
